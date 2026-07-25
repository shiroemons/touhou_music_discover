# frozen_string_literal: true

require 'jwt'

module AppleMusic
  class Config
    # 発行する JWT の有効期間と、期限切れ前に再発行を始めるマージン。
    TOKEN_TTL = 12.hours
    REFRESH_MARGIN = 10.minutes

    attr_accessor :secret_key_path, :secret_key, :team_id, :music_id, :storefront, :adapter

    def initialize
      @secret_key_path = ENV.fetch('APPLE_MUSIC_SECRET_KEY_PATH', nil)
      @secret_key = ENV.fetch('APPLE_MUSIC_SECRET_KEY', nil)
      @team_id = ENV.fetch('APPLE_MUSIC_TEAM_ID', nil)
      @music_id = ENV.fetch('APPLE_MUSIC_MUSIC_ID', nil)
      @storefront = ENV.fetch('APPLE_MUSIC_STOREFRONT', 'jp')
      @adapter = :net_http
      # AppleMusic.config は単一インスタンスを共有するため、キャッシュの
      # 判定と再生成をまとめて排他制御する。
      @token_mutex = Mutex.new
    end

    # ES256 の署名は毎回それなりのCPUコストがかかるため、有効期限までトークンを再利用する。
    def authentication_token
      @token_mutex.synchronize do
        @authentication_token = generate_authentication_token if token_refresh_required?
        @authentication_token
      end
    end

    private

    def token_refresh_required?
      @authentication_token.nil? || Time.current >= @token_expires_at - REFRESH_MARGIN
    end

    def generate_authentication_token
      private_key = OpenSSL::PKey::EC.new(secret_key_value)
      @token_expires_at = Time.current + TOKEN_TTL

      payload = {
        iss: team_id,
        iat: Time.current.to_i,
        exp: @token_expires_at.to_i
      }

      JWT.encode(payload, private_key, 'ES256', kid: music_id)
    end

    def secret_key_value
      return File.read(secret_key_path) if secret_key_path && File.exist?(secret_key_path)
      return secret_key if secret_key

      raise ParameterMissing, 'Either secret_key_path or secret_key must be provided'
    end
  end

  class ParameterMissing < StandardError; end

  class ApiError < StandardError
    attr_reader :response

    def initialize(message, response = nil)
      super(message)
      @response = response
    end
  end
end
