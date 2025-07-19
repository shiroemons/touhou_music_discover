# frozen_string_literal: true

require 'json'
require 'faraday'
require 'faraday/retry'

module LineMusic
  class ApiError < StandardError; end
  class ParameterMissing < StandardError; end

  API_URI = 'https://music.line.me/api2/'

  class Client
    class << self
      def client
        @client ||= Faraday.new(API_URI) do |conn|
          conn.request :retry, max: 3,
                               interval: 30,
                               interval_randomness: 0,
                               backoff_factor: 1,
                               exceptions: [Faraday::ConnectionFailed, Faraday::TimeoutError]
          conn.request :json
          conn.response :json, content_type: /\bjson$/
          conn.response :logger, Rails.logger, { headers: false, bodies: false } if Rails.env.development?
          conn.options.open_timeout = 5
          conn.options.timeout = 10
        end
      end

      def method_missing(name, *, &)
        if client.respond_to?(name)
          client.send(name, *, &)
        else
          super
        end
      end

      def respond_to_missing?(name, include_private = false)
        client.respond_to?(name, include_private)
      end
    end
  end
end
