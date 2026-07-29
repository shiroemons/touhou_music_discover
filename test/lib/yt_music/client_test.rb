# frozen_string_literal: true

require 'test_helper'

module YtMusic
  class ClientTest < ActiveSupport::TestCase
    setup do
      @original_cookie = ENV.fetch('YOUTUBE_MUSIC_COOKIE', nil)
      Client.instance_variable_set(:@sapisid, nil)
    end

    teardown do
      ENV['YOUTUBE_MUSIC_COOKIE'] = @original_cookie
      Client.instance_variable_set(:@sapisid, nil)
    end

    test 'extracts SAPISID from a cookie header with multiple cookies' do
      ENV['YOUTUBE_MUSIC_COOKIE'] = 'HSID=abc; SAPISID=xyz123; SSID=def'

      assert_equal 'xyz123', Client.send(:sapisid)
    end

    test 'unescapes url encoded cookie values' do
      ENV['YOUTUBE_MUSIC_COOKIE'] = 'HSID=abc; SAPISID=xyz%3D123'

      assert_equal 'xyz=123', Client.send(:sapisid)
    end

    test 'takes the first value when the cookie value contains an ampersand' do
      ENV['YOUTUBE_MUSIC_COOKIE'] = 'SAPISID=first&second'

      assert_equal 'first', Client.send(:sapisid)
    end

    test 'prefers the first occurrence when the same cookie appears twice' do
      ENV['YOUTUBE_MUSIC_COOKIE'] = 'SAPISID=first; SAPISID=second'

      assert_equal 'first', Client.send(:sapisid)
    end

    test 'returns nil when the cookie environment variable is not set' do
      ENV.delete('YOUTUBE_MUSIC_COOKIE')

      assert_nil Client.send(:sapisid)
    end

    test 'returns nil when the cookie environment variable is empty' do
      ENV['YOUTUBE_MUSIC_COOKIE'] = ''

      assert_nil Client.send(:sapisid)
    end

    test 'returns nil when the cookie header has no SAPISID' do
      ENV['YOUTUBE_MUSIC_COOKIE'] = 'HSID=abc; SSID=def'

      assert_nil Client.send(:sapisid)
    end

    test 'ignores malformed entries without a delimiter' do
      ENV['YOUTUBE_MUSIC_COOKIE'] = 'broken; SAPISID=xyz123'

      assert_equal 'xyz123', Client.send(:sapisid)
    end

    test 'client uses the shared yt_music connection profile' do
      assert_yt_music_profile Client.send(:client)
    end

    test 'youtube_client uses the shared yt_music connection profile' do
      assert_yt_music_profile Client.send(:youtube_client)
    end

    test 'raises a request error with the HTTP status for a failed response' do
      response = Faraday::Response.new(status: 403, response_body: 'Forbidden')

      error = assert_raises(RequestError) { Client.send(:validate_response, response) }

      assert_equal 403, error.status
      assert_equal 'YouTube Music API request failed (HTTP 403)', error.message
    end

    test 'raises a request error when a successful response is not a JSON object' do
      response = Faraday::Response.new(status: 200, response_body: '<html>unexpected</html>')

      error = assert_raises(RequestError) { Client.send(:validate_response, response) }

      assert_equal 200, error.status
      assert_match(/expected a JSON object/, error.message)
    end

    test 'converts an exhausted retriable response into a request error' do
      response = Faraday::Response.new(status: 403, response_body: 'Forbidden')
      retriable_error = Faraday::RetriableResponse.new(nil, response)

      error = assert_raises(RequestError) do
        Client.send(:execute_request) { raise retriable_error }
      end

      assert_equal 403, error.status
      assert_equal 'YouTube Music API request failed (HTTP 403)', error.message
    end

    private

    def assert_yt_music_profile(conn)
      assert_equal 5, conn.options.open_timeout
      assert_equal 15, conn.options.timeout
      assert_includes conn.builder.handlers.map(&:klass), Faraday::Retry::Middleware
      assert_includes conn.builder.handlers.map(&:klass), Faraday::Response::Json
    end
  end
end
