# frozen_string_literal: true

module SpotifyApi
  # パスに先頭スラッシュを付けないこと。ベース URL が https://api.spotify.com/v1/
  # なので、先頭スラッシュを付けると /v1 が消えてしまう（'albums/xxx' であって '/albums/xxx' ではない）。
  class Album
    class << self
      # テストから Client を差し替えるための注入口（SpotifyApi::Album.client = fake_client）。
      attr_writer :client

      # market を指定すると Spotify は available_markets を返さず is_playable に
      # 置き換わるため、既定では market を送らない。
      #
      # market を付けて呼び出すと SpotifyAlbum#jp_available?（app/models/spotify_album.rb）が
      # 参照している available_markets が取得できなくなり、日本で配信中のアルバムが
      # 「配信終了」と誤判定されて削除される危険がある。呼び出し側が明示的に
      # market を渡したときだけ付けること。
      def find(id, market: nil)
        params = {}
        params[:market] = market if market.present?

        Response.build(client.get("albums/#{id}", params))
      end

      # GET /albums?ids= のバルク取得エンドポイントは2026年2月に廃止が告知されているため
      # 使わず、1件ずつ逐次取得する。取得できなかった ID（404）は例外にせず結果から除外し
      # warn ログを出す。それ以外の例外（429 など）はそのまま伝播させ、呼び出し側の
      # SpotifyRetry / SpotifyRateLimit に委ねる（レート制限を握りつぶさない）。
      def find_many(ids, market: nil)
        ids.filter_map do |id|
          find(id, market:)
        rescue NotFoundError
          Rails.logger.warn("SpotifyApi::Album.find_many: album not found (id=#{id})")
          nil
        end
      end

      def tracks(id, limit: nil, offset: nil, market: nil)
        params = {}
        params[:limit] = limit if limit
        params[:offset] = offset if offset
        params[:market] = market if market.present?

        Page.build(client.get("albums/#{id}/tracks", params))
      end

      # limit の既定は SpotifyApi.config.search_limit（定数ではなく設定値。
      # Development Mode では取得件数の上限が下がるため）。
      # market の既定は SpotifyApi.config.market（'JP'）。
      def search(query, limit: SpotifyApi.config.search_limit, offset: nil, market: SpotifyApi.config.market)
        params = { q: query, type: 'album', limit:, market: }
        params[:offset] = offset if offset

        body = client.get('search', params)
        Page.build(body['albums'])
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
