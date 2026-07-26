# frozen_string_literal: true

require 'omniauth-oauth2'

module OmniAuth
  module Strategies
    # Spotify の Authorization Code フロー用 OmniAuth ストラテジ。
    #
    # 以前は rspotify gem 同梱の 'rspotify/oauth' を使っていたが、rspotify は
    # Issue #563 で削除予定であり、また RSpotify::User がトークンをプロセス
    # グローバルなクラス変数に持つ設計を引き継ぎたくないため自前で実装する。
    #
    # info のキー構造は app/models/user.rb が読む形（display_name / id / email /
    # images の配列）を保つこと。ここを変えると既存ユーザーの取り込みが壊れる。
    class Spotify < OmniAuth::Strategies::OAuth2
      option :name, 'spotify'

      option :client_options,
             site: 'https://accounts.spotify.com',
             authorize_url: '/authorize',
             token_url: '/api/token'

      uid { raw_info['id'] }

      info do
        {
          id: raw_info['id'],
          display_name: raw_info['display_name'],
          name: raw_info['display_name'],
          nickname: raw_info['display_name'],
          email: raw_info['email'],
          images: raw_info['images'] || [],
          external_urls: raw_info['external_urls'],
          followers: raw_info['followers'],
          href: raw_info['href'],
          uri: raw_info['uri']
        }
      end

      extra do
        { raw_info: }
      end

      def raw_info
        @raw_info ||= access_token.get('v1/me').parsed
      end

      # OmniAuth 2 系では callback_url に query string が含まれるとトークン交換で
      # redirect_uri 不一致になるため、query を落とす。
      def callback_url
        full_host + callback_path
      end
    end
  end
end

OmniAuth.config.add_camelization('spotify', 'Spotify')
