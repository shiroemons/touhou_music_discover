# frozen_string_literal: true

require 'test_helper'

module ExternalApi
  class ConnectionTest < ActiveSupport::TestCase
    EXPECTED_TIMEOUTS = {
      yt_music: { open_timeout: 5, timeout: 15 },
      line_music: { open_timeout: 5, timeout: 10 },
      apple_music: { open_timeout: 5, timeout: 15 },
      github: { open_timeout: 5, timeout: 30 },
      spotify: { open_timeout: 5, timeout: 15 },
      spotify_accounts: { open_timeout: 5, timeout: 10 }
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

    # spotify / spotify_accounts は 429 を意図的に除外しているため、この共通アサーションの対象外にする。
    test 'every profile except spotify and spotify_accounts retries on rate limit and server error statuses' do
      (Connection::PROFILES.keys - %i[spotify spotify_accounts]).each do |service|
        conn = Connection.build(service, url: 'https://example.com')

        assert_equal [429, 500, 502, 503, 504], retry_options(conn)[:retry_statuses], "#{service} の retry_statuses が想定と異なります"
      end
    end

    test 'spotify profile excludes 429 from the retry statuses' do
      conn = Connection.build(:spotify, url: 'https://example.com')
      retry_statuses = retry_options(conn)[:retry_statuses]

      assert_equal [500, 502, 503, 504], retry_statuses
      assert_not_includes retry_statuses, 429
    end

    test 'spotify_accounts profile excludes 429 from the retry statuses and retries post' do
      conn = Connection.build(:spotify_accounts, url: 'https://example.com')
      options = retry_options(conn)

      assert_equal [500, 502, 503, 504], options[:retry_statuses]
      assert_not_includes options[:retry_statuses], 429
      assert_includes options[:methods], :post
    end

    test 'profile retry options override the shared retry options' do
      conn = Connection.build(:spotify, url: 'https://example.com')

      assert_not_equal Connection::SHARED_RETRY_OPTIONS[:retry_statuses], retry_options(conn)[:retry_statuses]
      # 上書きしていないキーは共通設定がそのまま残る。
      assert_equal Connection::SHARED_RETRY_OPTIONS[:exceptions], retry_options(conn)[:exceptions]
    end

    private

    def retry_options(conn)
      retry_handler(conn).instance_variable_get(:@kwargs)
    end

    def retry_handler(conn)
      conn.builder.handlers.find { |handler| handler.klass == Faraday::Retry::Middleware }
    end

    def retry_handler?(conn)
      retry_handler(conn).present?
    end
  end
end
