# frozen_string_literal: true

module SpotifyApi
  class AudioFeatures
    # audio-features?ids= に一度に渡せる ID 数の上限（Spotify の仕様）。
    MAX_IDS_PER_REQUEST = 100

    class << self
      # テストから Client を差し替えるための注入口（SpotifyApi::AudioFeatures.client = fake_client）。
      attr_writer :client

      # audio-features は Spotify で deprecated 扱いのエンドポイントであるため、
      # 403 / 404 が返った場合は例外を伝播させず nil を返す。将来エンドポイントが
      # 完全に廃止されたときに、楽曲取得バッチ全体が落ちないようにするための防御。
      # それ以外の例外（401 / 429 / 5xx）はレート制限を握りつぶさないよう伝播させる。
      def find(id)
        Response.build(client.get("audio-features/#{id}"))
      rescue ForbiddenError, NotFoundError => e
        Rails.logger.warn("SpotifyApi::AudioFeatures.find: unavailable (#{e.class}, id=#{id})")
        nil
      end

      # ids は Spotify の上限（100件）に合わせて分割し、複数回リクエストする。
      # レスポンスの audio_features 配列には該当なしのトラックが null として
      # 混ざるため、結果から除外する。
      def find_many(ids)
        ids.each_slice(MAX_IDS_PER_REQUEST).flat_map { |batch| fetch_batch(batch) }
      end

      # テスト間で注入した Client が漏れないよう、teardown で必ず呼ぶこと。
      def reset_client!
        @client = nil
      end

      private

      def fetch_batch(ids)
        body = client.get('audio-features', { ids: ids.join(',') })
        Response.build(body['audio_features']).compact
      rescue ForbiddenError, NotFoundError => e
        Rails.logger.warn("SpotifyApi::AudioFeatures.find_many: unavailable (#{e.class})")
        []
      end

      def client
        @client ||= Client.new
      end
    end
  end
end
