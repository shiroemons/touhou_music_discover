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

    private

    def assert_yt_music_profile(conn)
      assert_equal 5, conn.options.open_timeout
      assert_equal 15, conn.options.timeout
      assert_includes conn.builder.handlers.map(&:klass), Faraday::Retry::Middleware
      assert_includes conn.builder.handlers.map(&:klass), Faraday::Response::Json
    end
  end
end
