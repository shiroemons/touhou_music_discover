# frozen_string_literal: true

require 'test_helper'

module SpotifyApi
  class ConfigTest < ActiveSupport::TestCase
    JSON_HEADERS = { 'Content-Type' => 'application/json' }.freeze

    setup do
      @stubs = Faraday::Adapter::Test::Stubs.new
      @config = Config.new
      @config.client_id = 'CLIENT_ID'
      @config.client_secret = 'CLIENT_SECRET'
      @config.token_connection = Faraday.new do |conn|
        conn.response :json, content_type: /\bjson$/
        conn.adapter :test, @stubs
      end
    end

    test 'reuses the cached token while it is still valid' do
      calls = stub_token('TOKEN', expires_in: 3600)

      token = @config.access_token

      assert_equal 'TOKEN', token
      assert_equal token, @config.access_token

      travel_to 3600.seconds.from_now - Config::REFRESH_MARGIN - 1.minute do
        assert_equal token, @config.access_token
      end

      assert_equal 1, calls.value
    end

    test 'refetches the token once the refresh margin is reached' do
      calls = stub_token(%w[FIRST SECOND], expires_in: 3600)

      assert_equal 'FIRST', @config.access_token

      travel_to 3600.seconds.from_now - Config::REFRESH_MARGIN + 1.minute do
        assert_equal 'SECOND', @config.access_token
      end

      assert_equal 2, calls.value
    end

    test 'falls back to DEFAULT_TOKEN_TTL when the response has no expires_in' do
      calls = stub_token(%w[FIRST SECOND], expires_in: nil)

      assert_equal 'FIRST', @config.access_token

      travel_to Config::DEFAULT_TOKEN_TTL.seconds.from_now - Config::REFRESH_MARGIN - 1.minute do
        assert_equal 'FIRST', @config.access_token
      end

      travel_to Config::DEFAULT_TOKEN_TTL.seconds.from_now - Config::REFRESH_MARGIN + 1.minute do
        assert_equal 'SECOND', @config.access_token
      end

      assert_equal 2, calls.value
    end

    test 'reset_token! discards the cached token' do
      calls = stub_token(%w[FIRST SECOND], expires_in: 3600)

      assert_equal 'FIRST', @config.access_token

      @config.reset_token!

      assert_equal 'SECOND', @config.access_token
      assert_equal 2, calls.value
    end

    test 'raises ConfigurationError when the credentials are blank' do
      @config.client_id = nil

      assert_raises(ConfigurationError) { @config.access_token }

      @config.client_id = 'CLIENT_ID'
      @config.client_secret = ''

      assert_raises(ConfigurationError) { @config.access_token }
    end

    test 'raises AuthenticationError when the token endpoint fails' do
      @stubs.post('/api/token') { [401, JSON_HEADERS, { error: 'invalid_client' }.to_json] }

      error = assert_raises(AuthenticationError) { @config.access_token }

      assert_equal 401, error.status
      assert_not_nil error.response
    end

    test 'sends basic authentication and the client credentials grant' do
      request_headers = nil
      request_body = nil
      @stubs.post('/api/token') do |env|
        # env はレスポンス処理で書き換えられるため、リクエスト内容はこの時点で控える。
        request_headers = env.request_headers.dup
        request_body = env.body
        [200, JSON_HEADERS, { access_token: 'TOKEN', expires_in: 3600 }.to_json]
      end

      @config.access_token

      assert_equal "Basic #{Base64.strict_encode64('CLIENT_ID:CLIENT_SECRET')}", request_headers['Authorization']
      assert_equal 'application/x-www-form-urlencoded', request_headers['Content-Type']
      assert_equal 'grant_type=client_credentials', request_body
    end

    test 'fetches the token only once when called from multiple threads' do
      calls = stub_token('TOKEN', expires_in: 3600, delay: 0.05)

      tokens = Array.new(5) { Thread.new { @config.access_token } }.map(&:value)

      assert_equal ['TOKEN'] * 5, tokens
      assert_equal 1, calls.value
    end

    private

    # トークンエンドポイントをスタブし、呼び出し回数を数えるカウンタを返す。
    # tokens に配列を渡すと、呼び出しごとに先頭から順に返す。
    def stub_token(tokens, expires_in:, delay: nil)
      queue = Array(tokens)
      calls = Concurrent::AtomicFixnum.new(0)

      @stubs.post('/api/token') do
        calls.increment
        sleep delay if delay
        body = { access_token: queue.length > 1 ? queue.shift : queue.first }
        body[:expires_in] = expires_in if expires_in
        [200, JSON_HEADERS, body.to_json]
      end

      calls
    end
  end
end
