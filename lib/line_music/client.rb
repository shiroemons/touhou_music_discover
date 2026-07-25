# frozen_string_literal: true

require 'json'

module LineMusic
  class ApiError < StandardError; end
  class ParameterMissing < StandardError; end

  API_URI = 'https://music.line.me/api2/'

  class Client
    # クラス変数へのメモ化を複数スレッドから同時に行うと、コネクションが二重に
    # 生成されうるため排他制御する。
    CLIENT_MUTEX = Mutex.new

    class << self
      def client
        CLIENT_MUTEX.synchronize do
          @client ||= ExternalApi::Connection.build(:line_music, url: API_URI) do |conn|
            conn.request :json
            conn.response :json, content_type: /\bjson$/
          end
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
