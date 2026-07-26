# frozen_string_literal: true

require 'test_helper'

module SpotifyApi
  class ClientTest < ActiveSupport::TestCase
    JSON_HEADERS = { 'Content-Type' => 'application/json' }.freeze
    # access_token を返すだけの設定オブジェクト。トークン取得の HTTP を挟まずに済む。
    FakeConfig = Struct.new(:access_token, :adapter)

    ERROR_CASES = {
      401 => AuthenticationError,
      403 => ForbiddenError,
      404 => NotFoundError,
      429 => RateLimitError,
      500 => ServerError,
      503 => ServerError,
      418 => ApiError
    }.freeze

    setup do
      @stubs = Faraday::Adapter::Test::Stubs.new
      @config = FakeConfig.new('APP_TOKEN', :test)
    end

    test 'the default connection uses the shared spotify profile' do
      conn = Client.new(Config.new).send(:connection)
      handlers = conn.builder.handlers.map(&:klass)

      assert_equal 5, conn.options.open_timeout
      assert_equal 15, conn.options.timeout
      assert_includes handlers, Faraday::Retry::Middleware
      assert_includes handlers, Faraday::Request::Json
      assert_includes handlers, Faraday::Response::Json
      assert_includes handlers, Faraday::Request::Authorization
    end

    ERROR_CASES.each do |status, error_class|
      test "raises #{error_class} for status #{status}" do
        stub_get { [status, JSON_HEADERS, { error: { status:, message: 'boom' } }.to_json] }

        error = assert_raises(error_class) { build_client.get('albums/1') }

        assert_instance_of error_class, error
        assert_equal status, error.status
        assert_equal 'boom', error.message
        assert_not_nil error.response
      end
    end

    test 'returns the parsed body for a successful response' do
      stub_get { [200, JSON_HEADERS, { id: '1', name: 'album' }.to_json] }

      assert_equal({ 'id' => '1', 'name' => 'album' }, build_client.get('albums/1'))
    end

    test 'returns nil for a response without a body' do
      @stubs.delete('/v1/playlists/1/tracks') { [204, {}, nil] }

      assert_nil build_client.delete('playlists/1/tracks')
    end

    test 'raises QuotaExceededError when the 429 reason is QUOTA_EXCEEDED' do
      stub_get do
        [429, JSON_HEADERS.merge('Retry-After' => '64063'),
         { error: { status: 429, reason: 'QUOTA_EXCEEDED', message: 'quota exceeded' } }.to_json]
      end

      # QuotaExceededError は RateLimitError を継承しているため、こちらでも rescue できる。
      error = assert_raises(RateLimitError) { build_client.get('albums/1') }

      assert_instance_of QuotaExceededError, error
      assert_equal 64_063, error.retry_after
    end

    test 'exposes the Retry-After header on a rate limit error' do
      stub_get { [429, JSON_HEADERS.merge('Retry-After' => '30'), { error: { status: 429, message: 'rate limited' } }.to_json] }

      error = assert_raises(RateLimitError) { build_client.get('albums/1') }

      assert_instance_of RateLimitError, error
      assert_equal 30, error.retry_after
    end

    test 'retry_after is nil when the Retry-After header is absent' do
      stub_get { [429, JSON_HEADERS, { error: { status: 429, message: 'rate limited' } }.to_json] }

      error = assert_raises(RateLimitError) { build_client.get('albums/1') }

      assert_nil error.retry_after
    end

    test 'falls back to a generic message when the body has no error message' do
      stub_get { [500, {}, ''] }

      error = assert_raises(ServerError) { build_client.get('albums/1') }

      assert_equal 'Spotify API request failed with status 500', error.message
    end

    test 'sends the application token as a bearer token' do
      request_headers = capture_request_headers

      build_client(with_authorization: true).get('albums/1')

      assert_equal 'Bearer APP_TOKEN', request_headers[:value]['Authorization']
    end

    test 'prefers the explicitly given access token over the application token' do
      request_headers = capture_request_headers

      build_client(with_authorization: true).get('albums/1', {}, access_token: 'USER_TOKEN')

      assert_equal 'Bearer USER_TOKEN', request_headers[:value]['Authorization']
    end

    test 'builds query parameters for get' do
      url = {}
      @stubs.get('/v1/search') do |env|
        url[:value] = env.url
        [200, JSON_HEADERS, '{}']
      end

      build_client.get('search', { q: 'touhou', type: 'album' })

      assert_equal 'q=touhou&type=album', url[:value].query
    end

    test 'sends a json body for post' do
      body = {}
      @stubs.post('/v1/playlists/1/tracks') do |env|
        body[:value] = env.body
        [201, JSON_HEADERS, { snapshot_id: 'abc' }.to_json]
      end

      result = build_client.post('playlists/1/tracks', { uris: ['spotify:track:1'] })

      assert_equal({ 'uris' => ['spotify:track:1'] }, JSON.parse(body[:value]))
      assert_equal({ 'snapshot_id' => 'abc' }, result)
    end

    test 'sends a json body for put' do
      body = {}
      @stubs.put('/v1/playlists/1') do |env|
        body[:value] = env.body
        [200, JSON_HEADERS, '{}']
      end

      build_client.put('playlists/1', { name: 'renamed' })

      assert_equal({ 'name' => 'renamed' }, JSON.parse(body[:value]))
    end

    test 'sends a json body for delete' do
      body = {}
      @stubs.delete('/v1/playlists/1/tracks') do |env|
        body[:value] = env.body
        [200, JSON_HEADERS, { snapshot_id: 'abc' }.to_json]
      end

      build_client.delete('playlists/1/tracks', { tracks: [{ uri: 'spotify:track:1' }] })

      assert_equal({ 'tracks' => [{ 'uri' => 'spotify:track:1' }] }, JSON.parse(body[:value]))
    end

    private

    # 例外マッピングの検証には retry ミドルウェアの無い素の Faraday を使う。
    # 既定のコネクションでは 5xx のたびにリトライ待機が入りテストが遅くなるため。
    def build_client(with_authorization: false)
      config = @config
      connection = Faraday.new(url: Config::API_URL) do |conn|
        conn.request :json
        conn.response :json, content_type: /\bjson$/
        conn.request(:authorization, 'Bearer', -> { config.access_token }) if with_authorization
        conn.adapter :test, @stubs
      end

      Client.new(config, connection:)
    end

    def stub_get(&)
      @stubs.get('/v1/albums/1', &)
    end

    def capture_request_headers
      headers = {}
      stub_get do |env|
        headers[:value] = env.request_headers.dup
        [200, JSON_HEADERS, '{}']
      end
      headers
    end
  end
end
