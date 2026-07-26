# frozen_string_literal: true

require 'base64'

module SpotifyApi
  class Config
    ACCOUNTS_URL = 'https://accounts.spotify.com'
    API_URL = 'https://api.spotify.com/v1/'
    DEFAULT_TOKEN_TTL = 3600      # Spotify の既定。expires_in が無い場合のフォールバック
    REFRESH_MARGIN = 60.seconds   # 期限切れ前に再取得を始めるマージン

    # フィーチャーフラグの ENV を true とみなす値（大文字小文字は問わない）。
    TRUTHY_VALUES = %w[1 true yes on].freeze

    attr_accessor :client_id, :client_secret, :market, :search_limit, :adapter, :native_client_enabled, :playlist_items_path
    attr_writer :token_connection

    def initialize
      @client_id = ENV.fetch('SPOTIFY_CLIENT_ID', nil)
      @client_secret = ENV.fetch('SPOTIFY_CLIENT_SECRET', nil)
      @market = 'JP'
      # Development Mode では検索の取得件数上限が下がるため、定数ではなく設定値にする。
      @search_limit = ENV.fetch('SPOTIFY_SEARCH_LIMIT', 50).to_i
      @adapter = :net_http
      # 既定は true（SpotifyApi のネイティブ経路）。SPOTIFY_NATIVE_CLIENT=0 / false / no / off で
      # 旧 rspotify 経路に戻せる。ENV.fetch の既定値が使われるのはキーが「未設定」のときだけで、
      # 空文字はそのまま渡り TRUTHY_VALUES に含まれないため false になる。
      # つまり SPOTIFY_NATIVE_CLIENT=（空文字）は「未設定」ではなく明示的な opt-out として扱う。
      # これは不具合ではなく意図した挙動（設計書「設定変更」参照）。
      @native_client_enabled = truthy?(ENV.fetch('SPOTIFY_NATIVE_CLIENT', 'true'))
      # 2026年2月に /playlists/{id}/tracks → /playlists/{id}/items へのリネームが
      # 告知されたが、2026年3月9日に既存インテグレーション向けの適用は延期された。
      # 動作実績があるのは /tracks のため、既定はそちらにする（詳細は Playlist 参照）。
      @playlist_items_path = ENV.fetch('SPOTIFY_PLAYLIST_ITEMS_PATH', 'tracks')
      # SpotifyApi.config は単一インスタンスを共有するため、キャッシュの
      # 判定と再取得をまとめて排他制御する。
      @token_mutex = Mutex.new
    end

    # Client Credentials フローで取得したアクセストークン。有効期限まで再利用する。
    #
    # トークン取得は起動時ではなく最初の API 呼び出し時に行う（遅延取得）。
    # config/initializers/rspotify.rb は after_initialize で先に認証しているが、
    # その方式でも Spotify 側の障害時には起動が重くなるため、SpotifyApi では
    # 初期化時にネットワークI/Oを一切走らせない方針をとる。
    def access_token
      @token_mutex.synchronize do
        fetch_access_token if token_refresh_required?
        @access_token
      end
    end

    # キャッシュ済みトークンを破棄し、次回アクセス時に再取得させる。
    def reset_token!
      @token_mutex.synchronize do
        @access_token = nil
        @token_expires_at = nil
      end
    end

    # トークン取得専用のコネクション。
    #
    # Bearer 認証ミドルウェアを付けてはいけない。トークンを取得するための
    # リクエストがトークンを要求する鶏卵問題になるため。
    def token_connection
      @token_connection ||= ExternalApi::Connection.build(:spotify_accounts, url: ACCOUNTS_URL, adapter:) do |conn|
        conn.response :json, content_type: /\bjson$/
      end
    end

    private

    def token_refresh_required?
      @access_token.nil? || Time.current >= @token_expires_at - REFRESH_MARGIN
    end

    def fetch_access_token
      raise ConfigurationError, 'client_id and client_secret must be provided' if client_id.blank? || client_secret.blank?

      response = request_access_token
      raise AuthenticationError.new("Failed to fetch Spotify access token with status #{response.status}", status: response.status, response:) unless response.status == 200

      body = response.body || {}
      @access_token = body['access_token']
      @token_expires_at = Time.current + (body['expires_in'] || DEFAULT_TOKEN_TTL).to_i
    end

    def request_access_token
      token_connection.post('/api/token') do |req|
        req.headers['Authorization'] = "Basic #{Base64.strict_encode64("#{client_id}:#{client_secret}")}"
        req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
        req.body = URI.encode_www_form(grant_type: 'client_credentials')
      end
    end

    def truthy?(value)
      TRUTHY_VALUES.include?(value.to_s.strip.downcase)
    end
  end
end
