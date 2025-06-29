# frozen_string_literal: true

require 'jwt'

module AppleMusic
  class Config
    attr_accessor :secret_key_path, :secret_key, :team_id, :music_id, :storefront, :adapter

    def initialize
      @secret_key_path = ENV.fetch('APPLE_MUSIC_SECRET_KEY_PATH', nil)
      @secret_key = ENV.fetch('APPLE_MUSIC_SECRET_KEY', nil)
      @team_id = ENV.fetch('APPLE_MUSIC_TEAM_ID', nil)
      @music_id = ENV.fetch('APPLE_MUSIC_MUSIC_ID', nil)
      @storefront = ENV.fetch('APPLE_MUSIC_STOREFRONT', 'jp')
      @adapter = :net_http
    end

    def authentication_token
      private_key = OpenSSL::PKey::EC.new(secret_key_value)

      payload = {
        iss: team_id,
        iat: Time.now.to_i,
        exp: Time.now.to_i + 86_400 # 24 hours
      }

      JWT.encode(payload, private_key, 'ES256', kid: music_id)
    end

    private

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
