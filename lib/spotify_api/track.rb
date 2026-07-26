# frozen_string_literal: true

module SpotifyApi
  class Track
    class << self
      # テストから Client を差し替えるための注入口（SpotifyApi::Track.client = fake_client）。
      attr_writer :client

      def find(id, market: nil)
        params = {}
        params[:market] = market if market.present?

        Response.build(client.get("tracks/#{id}", params))
      end

      # Album.find_many と同じ方針。GET /tracks?ids= のバルク取得エンドポイントは
      # 使わず1件ずつ逐次取得する。404 は例外にせず結果から除外して warn ログを出し、
      # それ以外の例外（429 など）はそのまま伝播させる（レート制限を握りつぶさない）。
      def find_many(ids, market: nil)
        ids.filter_map do |id|
          find(id, market:)
        rescue NotFoundError
          Rails.logger.warn("SpotifyApi::Track.find_many: track not found (id=#{id})")
          nil
        end
      end

      # テスト間で注入した Client が漏れないよう、teardown で必ず呼ぶこと。
      def reset_client!
        @client = nil
      end

      private

      def client
        @client ||= Client.new
      end
    end
  end
end
