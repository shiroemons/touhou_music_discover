# frozen_string_literal: true

require 'test_helper'

module SpotifyApi
  class AlbumTest < ActiveSupport::TestCase
    JSON_HEADERS = { 'Content-Type' => 'application/json' }.freeze
    FakeConfig = Struct.new(:access_token, :adapter)

    setup do
      @stubs = Faraday::Adapter::Test::Stubs.new
      Album.client = build_client
    end

    teardown do
      # 差し込んだ Client がテスト間で漏れないよう、必ずリセットする。
      Album.reset_client!
    end

    test 'find does not send a market parameter by default' do
      query = capture_query('/v1/albums/123', { id: '123', name: 'album' })

      Album.find('123')

      assert_nil query[:value]
    end

    test 'find sends market only when explicitly given' do
      query = capture_query('/v1/albums/123', { id: '123' })

      Album.find('123', market: 'JP')

      assert_equal 'market=JP', query[:value]
    end

    test 'find wraps the response body' do
      @stubs.get('/v1/albums/123') { [200, JSON_HEADERS, { id: '123', name: 'album' }.to_json] }

      album = Album.find('123')

      assert_instance_of Response, album
      assert_equal 'album', album.name
    end

    test 'find_many fetches each id individually instead of using the bulk endpoint' do
      @stubs.get('/v1/albums/1') { [200, JSON_HEADERS, { id: '1' }.to_json] }
      @stubs.get('/v1/albums/2') { [200, JSON_HEADERS, { id: '2' }.to_json] }

      albums = Album.find_many(%w[1 2])

      assert_equal %w[1 2], albums.map(&:id)
    end

    test 'find_many skips ids that respond with 404' do
      @stubs.get('/v1/albums/1') { [200, JSON_HEADERS, { id: '1' }.to_json] }
      @stubs.get('/v1/albums/2') { [404, JSON_HEADERS, { error: { status: 404, message: 'not found' } }.to_json] }

      albums = Album.find_many(%w[1 2])

      assert_equal ['1'], albums.map(&:id)
    end

    test 'find_many propagates errors other than 404, such as rate limiting' do
      @stubs.get('/v1/albums/1') { [429, JSON_HEADERS, { error: { status: 429, message: 'rate limited' } }.to_json] }

      assert_raises(RateLimitError) { Album.find_many(%w[1]) }
    end

    test 'tracks builds the path and query parameters' do
      requested_path = {}
      query = {}
      @stubs.get('/v1/albums/123/tracks') do |env|
        requested_path[:value] = env.url.path
        query[:value] = env.url.query
        [200, JSON_HEADERS, { items: [] }.to_json]
      end

      Album.tracks('123', limit: 50, offset: 50)

      assert_equal '/v1/albums/123/tracks', requested_path[:value]
      assert_equal 'limit=50&offset=50', query[:value]
    end

    test 'tracks returns a Page' do
      @stubs.get('/v1/albums/123/tracks') { [200, JSON_HEADERS, { items: [{ id: 't1' }], total: 1 }.to_json] }

      page = Album.tracks('123')

      assert_instance_of Page, page
      assert_equal 't1', page.items.first.id
      assert_equal 1, page.total
    end

    test 'search sends the configured search_limit and market by default' do
      query = capture_query('/v1/search', { albums: { items: [] } })

      Album.search('touhou')

      params = URI.decode_www_form(query[:value]).to_h

      assert_equal 'touhou', params['q']
      assert_equal 'album', params['type']
      assert_equal SpotifyApi.config.search_limit.to_s, params['limit']
      assert_equal SpotifyApi.config.market, params['market']
    end

    test 'search returns a Page built from body["albums"]' do
      @stubs.get('/v1/search') { [200, JSON_HEADERS, { albums: { items: [{ id: 'a1' }], total: 1 } }.to_json] }

      page = Album.search('touhou')

      assert_instance_of Page, page
      assert_equal 'a1', page.items.first.id
    end

    test 'search returns an empty Page when the response has no albums key' do
      @stubs.get('/v1/search') { [200, JSON_HEADERS, {}.to_json] }

      page = Album.search('touhou')

      assert_instance_of Page, page
      assert_empty page
    end

    private

    def build_client
      connection = Faraday.new(url: Config::API_URL) do |conn|
        conn.request :json
        conn.response :json, content_type: /\bjson$/
        conn.adapter :test, @stubs
      end

      Client.new(FakeConfig.new('TOKEN', :test), connection:)
    end

    # 指定パスへのリクエストを1回だけ受け付け、クエリ文字列を記録するスタブを登録する。
    def capture_query(path, body)
      query = {}
      @stubs.get(path) do |env|
        query[:value] = env.url.query
        [200, JSON_HEADERS, body.to_json]
      end
      query
    end
  end
end
