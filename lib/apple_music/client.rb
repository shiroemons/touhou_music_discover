# frozen_string_literal: true

require 'faraday'
require 'faraday/net_http'

module AppleMusic
  class Client
    API_URI = 'https://api.music.apple.com/v1/'

    def initialize(config)
      @config = config
    end

    def get(path, params = {})
      response = connection.get(path, params)
      handle_response(response)
    end

    def post(path, body = {})
      response = connection.post(path, body) do |req|
        req.headers['Content-Type'] = 'application/json'
        req.body = body.to_json
      end
      handle_response(response)
    end

    private

    attr_reader :config

    def connection
      @connection ||= ExternalApi::Connection.build(:apple_music, url: API_URI, adapter: config.adapter) do |conn|
        conn.request :json
        conn.response :json, content_type: /\bjson$/
        # Proc を渡すとリクエストごとに評価されるため、JWT の期限切れ後も
        # 更新されたトークンが使われる（コネクション生成時の値に固定されない）。
        conn.request :authorization, 'Bearer', -> { config.authentication_token }
      end
    end

    def handle_response(response)
      case response.status
      when 200..299
        response.body
      when 401
        raise ApiError.new('Unauthorized. Please check your authentication credentials.', response)
      when 404
        raise ApiError.new('Resource not found.', response)
      when 429
        raise ApiError.new('Rate limit exceeded. Please try again later.', response)
      else
        error_message = response.body.dig('errors', 0, 'detail') || "Request failed with status #{response.status}"
        raise ApiError.new(error_message, response)
      end
    end
  end
end
