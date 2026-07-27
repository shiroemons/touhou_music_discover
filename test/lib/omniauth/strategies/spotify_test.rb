# frozen_string_literal: true

require 'test_helper'
require 'oauth2'

module OmniAuth
  module Strategies
    class SpotifyTest < ActiveSupport::TestCase
      # GET /v1/me の実レスポンス形状（値はすべて架空）
      RAW_INFO = {
        'account_id' => 'ACCOUNT123',
        'display_name' => 'Test User',
        'email' => 'test@example.com',
        'external_urls' => { 'spotify' => 'https://open.spotify.com/user/test-user' },
        'followers' => { 'href' => nil, 'total' => 3 },
        'href' => 'https://api.spotify.com/v1/users/test-user',
        'id' => 'test-user',
        'images' => [{ 'height' => 300, 'url' => 'https://example.test/avatar.png', 'width' => 300 }],
        'type' => 'user',
        'uri' => 'spotify:user:test-user'
      }.freeze

      def build_strategy(raw_info = RAW_INFO)
        strategy = Spotify.new(nil, 'client-id', 'client-secret')
        strategy.define_singleton_method(:raw_info) { raw_info }
        strategy
      end

      test 'uid comes from the Spotify user id' do
        assert_equal 'test-user', build_strategy.uid
      end

      test 'info keeps the keys app/models/user.rb reads' do
        info = build_strategy.info

        assert_equal 'test-user', info[:id]
        assert_equal 'Test User', info[:display_name]
        assert_equal 'test@example.com', info[:email]
        assert_equal 'https://example.test/avatar.png', info[:images][0]['url']
      end

      test 'info tolerates a user without images or email' do
        info = build_strategy(RAW_INFO.merge('images' => [], 'email' => nil)).info

        assert_equal [], info[:images]
        assert_nil info[:email]
      end

      test 'extra carries the raw payload' do
        assert_equal RAW_INFO, build_strategy.extra[:raw_info]
      end

      test 'client options point at the Spotify accounts service' do
        options = Spotify.new(nil, 'client-id', 'client-secret').options.client_options

        assert_equal 'https://accounts.spotify.com', options[:site]
        assert_equal '/authorize', options[:authorize_url]
        assert_equal '/api/token', options[:token_url]
      end

      test 'raw_info requests the Spotify Web API host, not the accounts host' do
        stub = stub_request(:get, 'https://api.spotify.com/v1/me')
               .to_return(status: 200, body: RAW_INFO.to_json,
                          headers: { 'Content-Type' => 'application/json' })

        strategy = Spotify.new(nil, 'client-id', 'client-secret')
        client = ::OAuth2::Client.new('client-id', 'client-secret',
                                      **Spotify.default_options[:client_options].to_h.symbolize_keys)
        token = ::OAuth2::AccessToken.new(client, 'USER_TOKEN')
        strategy.define_singleton_method(:access_token) { token }

        assert_equal 'test-user', strategy.raw_info['id']
        assert_requested stub
      end

      test 'auth hash exposes the image url with symbol keys, as app/models/user.rb reads it' do
        auth = OmniAuth::AuthHash.new(info: build_strategy.info)

        assert_equal 'https://example.test/avatar.png', auth[:info][:images][0][:url]
      end
    end
  end
end
