# frozen_string_literal: true

require 'test_helper'

module ExternalApi
  class ConnectionTest < ActiveSupport::TestCase
    EXPECTED_TIMEOUTS = {
      yt_music: { open_timeout: 5, timeout: 15 },
      line_music: { open_timeout: 5, timeout: 10 },
      apple_music: { open_timeout: 5, timeout: 15 },
      github: { open_timeout: 5, timeout: 30 }
    }.freeze

    EXPECTED_TIMEOUTS.each do |service, expected|
      test "#{service} profile applies the expected timeouts" do
        conn = Connection.build(service, url: 'https://example.com')

        assert_equal expected[:open_timeout], conn.options.open_timeout
        assert_equal expected[:timeout], conn.options.timeout
      end

      test "#{service} profile installs the retry middleware" do
        conn = Connection.build(service, url: 'https://example.com')

        assert retry_handler?(conn), "#{service} には Faraday::Retry::Middleware が必要です"
      end
    end

    test 'yields the connection before the adapter is set' do
      conn = Connection.build(:github, url: 'https://example.com') do |builder|
        builder.response :json
      end

      handler_names = conn.builder.handlers.map(&:klass)

      assert_includes handler_names, Faraday::Response::Json
      assert_equal Faraday::Adapter::NetHttp, conn.builder.adapter.klass
    end

    test 'uses the given adapter when specified' do
      conn = Connection.build(:apple_music, url: 'https://example.com', adapter: :test)

      assert_equal Faraday::Adapter::Test, conn.builder.adapter.klass
    end

    test 'raises for an unknown service' do
      error = assert_raises(Connection::UnknownService) do
        Connection.build(:unknown_service)
      end

      assert_match(/unknown_service/, error.message)
    end

    test 'every profile retries on rate limit and server error statuses' do
      Connection::PROFILES.each_key do |service|
        conn = Connection.build(service, url: 'https://example.com')
        options = retry_handler(conn).instance_variable_get(:@kwargs)

        assert_equal [429, 500, 502, 503, 504], options[:retry_statuses], "#{service} の retry_statuses が想定と異なります"
      end
    end

    private

    def retry_handler(conn)
      conn.builder.handlers.find { |handler| handler.klass == Faraday::Retry::Middleware }
    end

    def retry_handler?(conn)
      retry_handler(conn).present?
    end
  end
end
