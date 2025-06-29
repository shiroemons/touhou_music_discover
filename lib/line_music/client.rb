# frozen_string_literal: true

require 'json'
require 'faraday'

module LineMusic
  class ApiError < StandardError; end
  class ParameterMissing < StandardError; end

  API_URI = 'https://music.line.me/api2/'

  class Client
    class << self
      def client
        @client ||= Faraday.new(API_URI) do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson$/
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

  # 既存コードとの互換性のため、モジュールレベルでClientクラスのメソッドに委譲
  class << self
    def method_missing(name, *, &)
      if Client.respond_to?(name)
        Client.send(name, *, &)
      else
        super
      end
    end

    def respond_to_missing?(name, include_private = false)
      Client.respond_to?(name, include_private)
    end
  end
end
