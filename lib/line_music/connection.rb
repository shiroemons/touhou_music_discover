# frozen_string_literal: true

require 'json'
require 'faraday'
require 'faraday_middleware'

module LineMusic
  class ApiError < StandardError; end
  class ParameterMissing < StandardError; end

  API_URI = 'https://music.line.me/api2/'

  class << self
    private

    def client
      @client ||= Faraday.new(API_URI) do |conn|
        conn.response :json, content_type: /\bjson\z/
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
