# frozen_string_literal: true

require 'test_helper'

module SpotifyApi
  class PlaylistTest < ActiveSupport::TestCase
    JSON_HEADERS = { 'Content-Type' => 'application/json' }.freeze
    FakeConfig = Struct.new(:access_token, :adapter)
    FakeSession = Struct.new(:access_token, :spotify_user_id)

    setup do
      @stubs = Faraday::Adapter::Test::Stubs.new
      Playlist.client = build_client
      @session = FakeSession.new('USER_TOKEN', 'spotify-uid')
    end

    teardown do
      # 差し込んだ Client、記憶させた items_path / create のフォールバック先が
      # テスト間で漏れないよう、必ずリセットする。
      Playlist.reset_client!
      Playlist.reset_items_path!
    end

    test 'find requests playlists/{id} and wraps the response body' do
      requested_path = {}
      @stubs.get('/v1/playlists/pl1') do |env|
        requested_path[:value] = env.url.path
        [200, JSON_HEADERS, { id: 'pl1', name: 'Youkai Mountain' }.to_json]
      end

      playlist = Playlist.find(@session, 'pl1')

      assert_equal '/v1/playlists/pl1', requested_path[:value]
      assert_instance_of Response, playlist
      assert_equal 'Youkai Mountain', playlist.name
    end

    test 'requests are authorized with the session access token, not the application token' do
      Playlist.client = build_client(with_authorization: true)
      request_headers = {}
      @stubs.get('/v1/playlists/pl1') do |env|
        request_headers[:value] = env.request_headers.dup
        [200, JSON_HEADERS, { id: 'pl1' }.to_json]
      end

      Playlist.find(@session, 'pl1')

      assert_equal 'Bearer USER_TOKEN', request_headers[:value]['Authorization']
    end

    test 'items defaults to the /tracks path and forwards limit/offset' do
      requested_path = {}
      query = {}
      @stubs.get('/v1/playlists/pl1/tracks') do |env|
        requested_path[:value] = env.url.path
        query[:value] = env.url.query
        [200, JSON_HEADERS, { items: [{ id: 't1' }], total: 1 }.to_json]
      end

      page = Playlist.items(@session, 'pl1', limit: 50, offset: 100)

      assert_equal '/v1/playlists/pl1/tracks', requested_path[:value]
      assert_equal 'limit=50&offset=100', query[:value]
      assert_instance_of Page, page
      assert_equal 't1', page.items.first.id
    end

    test 'falls back to /items exactly once when /tracks responds 404, then remembers it' do
      tracks_calls = 0
      items_calls = 0

      @stubs.get('/v1/playlists/pl1/tracks') do
        tracks_calls += 1
        [404, JSON_HEADERS, { error: { status: 404, message: 'not found' } }.to_json]
      end
      @stubs.get('/v1/playlists/pl1/items') do
        items_calls += 1
        [200, JSON_HEADERS, { items: [{ id: 't1' }] }.to_json]
      end

      Playlist.items(@session, 'pl1')
      Playlist.items(@session, 'pl1')

      assert_equal 1, tracks_calls
      assert_equal 2, items_calls
    end

    # 429 でフォールバックすると、レート制限中に同じリクエストを2倍撃つことになる。
    # NotFoundError のとき以外は絶対にフォールバックしないことの回帰防止テスト。
    test 'does not fall back on a 429 response; the error propagates instead' do
      tracks_calls = 0
      items_calls = 0

      @stubs.get('/v1/playlists/pl1/tracks') do
        tracks_calls += 1
        [429, JSON_HEADERS.merge('Retry-After' => '30'), { error: { status: 429, message: 'rate limited' } }.to_json]
      end
      @stubs.get('/v1/playlists/pl1/items') do
        items_calls += 1
        [200, JSON_HEADERS, { items: [] }.to_json]
      end

      assert_raises(RateLimitError) { Playlist.items(@session, 'pl1') }

      assert_equal 1, tracks_calls
      assert_equal 0, items_calls
    end

    test 'mine requests me/playlists and returns a Page' do
      @stubs.get('/v1/me/playlists') { [200, JSON_HEADERS, { items: [{ id: 'p1' }], total: 1 }.to_json] }

      page = Playlist.mine(@session)

      assert_instance_of Page, page
      assert_equal 'p1', page.items.first.id
    end

    test 'create posts to me/playlists with name, public and description' do
      body = {}
      @stubs.post('/v1/me/playlists') do |env|
        body[:value] = JSON.parse(env.body)
        [201, JSON_HEADERS, { id: 'new-playlist' }.to_json]
      end

      playlist = Playlist.create(@session, name: 'Youkai Mountain', public: false, description: 'arrange songs')

      assert_equal({ 'name' => 'Youkai Mountain', 'public' => false, 'description' => 'arrange songs' }, body[:value])
      assert_equal 'new-playlist', playlist.id
    end

    # POST /users/{user_id}/playlists は廃止告知済みで、後継は POST /me/playlists。
    # me/playlists が 404 のときだけ廃止予定のパスへフォールバックし、以降はそちらを
    # 直接使うことを確認する。
    test 'falls back to users/{id}/playlists exactly once when me/playlists responds 404, then remembers it' do
      me_calls = 0
      users_calls = 0

      @stubs.post('/v1/me/playlists') do
        me_calls += 1
        [404, JSON_HEADERS, { error: { status: 404, message: 'not found' } }.to_json]
      end
      @stubs.post('/v1/users/spotify-uid/playlists') do
        users_calls += 1
        [201, JSON_HEADERS, { id: 'new-playlist' }.to_json]
      end

      Playlist.create(@session, name: 'Youkai Mountain')
      Playlist.create(@session, name: 'Another')

      assert_equal 1, me_calls
      assert_equal 2, users_calls
    end

    test 'add_items posts uris to the items path' do
      body = {}
      @stubs.post('/v1/playlists/pl1/tracks') do |env|
        body[:value] = JSON.parse(env.body)
        [201, JSON_HEADERS, { snapshot_id: 'snap1' }.to_json]
      end

      result = Playlist.add_items(@session, 'pl1', %w[spotify:track:1 spotify:track:2])

      assert_equal({ 'uris' => %w[spotify:track:1 spotify:track:2] }, body[:value])
      assert_equal 'snap1', result.snapshot_id
    end

    test 'remove_items sends a DELETE with a tracks body' do
      body = {}
      @stubs.delete('/v1/playlists/pl1/tracks') do |env|
        body[:value] = JSON.parse(env.body)
        [200, JSON_HEADERS, { snapshot_id: 'snap2' }.to_json]
      end

      result = Playlist.remove_items(@session, 'pl1', ['spotify:track:1'])

      assert_equal({ 'tracks' => [{ 'uri' => 'spotify:track:1' }] }, body[:value])
      assert_equal 'snap2', result.snapshot_id
    end

    test 'replace_items sends a PUT with a uris body' do
      body = {}
      @stubs.put('/v1/playlists/pl1/tracks') do |env|
        body[:value] = JSON.parse(env.body)
        [200, JSON_HEADERS, { snapshot_id: 'snap3' }.to_json]
      end

      result = Playlist.replace_items(@session, 'pl1', ['spotify:track:9'])

      assert_equal({ 'uris' => ['spotify:track:9'] }, body[:value])
      assert_equal 'snap3', result.snapshot_id
    end

    test 'all_items concatenates every page and stops at the last page' do
      @stubs.get('/v1/playlists/pl1/tracks') do |env|
        offset = URI.decode_www_form(env.url.query.to_s).to_h['offset'].to_i
        page_body(offset)
      end

      items = Playlist.all_items(@session, 'pl1', limit: 2)

      assert_equal %w[t1 t2 t3], items.map(&:id)
    end

    # total が信頼できない、あるいは next が終わらないレスポンスへの保険。
    # items が空のページを受け取った時点で必ず止まることを確認する（無限ループ防止）。
    test 'all_items stops as soon as a page returns no items' do
      calls = 0
      @stubs.get('/v1/playlists/pl1/tracks') do
        calls += 1
        [200, JSON_HEADERS,
         { items: [], total: 100, limit: 100, offset: 0,
           next: 'https://api.spotify.com/v1/playlists/pl1/tracks?offset=100&limit=100' }.to_json]
      end

      items = Playlist.all_items(@session, 'pl1')

      assert_equal [], items
      assert_equal 1, calls
    end

    private

    def page_body(offset)
      case offset
      when 0
        [200, JSON_HEADERS,
         { items: [{ id: 't1' }, { id: 't2' }], total: 3, limit: 2, offset: 0,
           next: 'https://api.spotify.com/v1/playlists/pl1/tracks?offset=2&limit=2' }.to_json]
      when 2
        [200, JSON_HEADERS, { items: [{ id: 't3' }], total: 3, limit: 2, offset: 2, next: nil }.to_json]
      else
        raise "unexpected offset #{offset}"
      end
    end

    def build_client(with_authorization: false)
      connection = Faraday.new(url: Config::API_URL) do |conn|
        conn.request :json
        conn.response :json, content_type: /\bjson$/
        conn.request(:authorization, 'Bearer', -> { 'APP_TOKEN' }) if with_authorization
        conn.adapter :test, @stubs
      end

      Client.new(FakeConfig.new('APP_TOKEN', :test), connection:)
    end
  end
end
