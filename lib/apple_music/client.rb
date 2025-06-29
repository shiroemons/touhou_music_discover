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
      @connection ||= Faraday.new(url: API_URI) do |conn|
        conn.request :json
        conn.response :json, content_type: /\bjson$/
        conn.adapter config.adapter
        conn.headers['Authorization'] = "Bearer #{config.authentication_token}"
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
