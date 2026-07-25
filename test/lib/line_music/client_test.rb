# frozen_string_literal: true

require 'test_helper'

module LineMusic
  class ClientTest < ActiveSupport::TestCase
    test 'client uses the shared line_music connection profile' do
      conn = Client.client

      assert_equal 5, conn.options.open_timeout
      assert_equal 10, conn.options.timeout
      assert_includes conn.builder.handlers.map(&:klass), Faraday::Retry::Middleware
      assert_includes conn.builder.handlers.map(&:klass), Faraday::Request::Json
      assert_includes conn.builder.handlers.map(&:klass), Faraday::Response::Json
    end

    test 'client is memoized' do
      assert_same Client.client, Client.client
    end

    test 'delegates unknown methods to the underlying connection' do
      assert_respond_to Client, :get
      assert_equal API_URI, Client.url_prefix.to_s
    end
  end
end
