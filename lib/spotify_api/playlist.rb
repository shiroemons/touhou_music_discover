# frozen_string_literal: true

module SpotifyApi
  # パスに先頭スラッシュを付けないこと（lib/spotify_api/album.rb 参照）。
  #
  # すべてのメソッドが UserSession のアクセストークンを使う。SpotifyApi::Config が
  # 管理するアプリトークン（Client Credentials）ではプレイリストの読み書きはできない。
  class Playlist
    # 自動ページング（all_items / all_mine）が辿るページ数の安全弁。
    # Spotify 側の不具合等で next が終わらず返り続けた場合に、無限ループで
    # プロセスがハングし続けるのを防ぐための保険。実運用でここに到達することは
    # 想定していない（MAX_PAGES × limit で数万〜数十万件相当）。
    MAX_PAGES = 1000

    class << self
      # テストから Client を差し替えるための注入口（SpotifyApi::Playlist.client = fake_client）。
      attr_writer :client

      def find(session, id)
        Response.build(client.get("playlists/#{id}", {}, access_token: session.access_token))
      end

      def items(session, id, limit: nil, offset: nil)
        params = {}
        params[:limit] = limit if limit
        params[:offset] = offset if offset

        Page.build(with_items_path_fallback(id) { |path| client.get(path, params, access_token: session.access_token) })
      end

      def all_items(session, id, limit: 100)
        fetch_all(limit:) { |offset| items(session, id, limit:, offset:) }
      end

      def mine(session, limit: nil, offset: nil)
        params = {}
        params[:limit] = limit if limit
        params[:offset] = offset if offset

        Page.build(client.get('me/playlists', params, access_token: session.access_token))
      end

      def all_mine(session, limit: 50)
        fetch_all(limit:) { |offset| mine(session, limit:, offset:) }
      end

      def create(session, name:, public: true, description: nil)
        body = { name:, public: }
        body[:description] = description if description.present?

        Response.build(request_create(session, body))
      end

      def add_items(session, id, uris)
        Response.build(with_items_path_fallback(id) { |path| client.post(path, { uris: }, access_token: session.access_token) })
      end

      def remove_items(session, id, uris)
        body = { tracks: uris.map { |uri| { uri: } } }
        Response.build(with_items_path_fallback(id) { |path| client.delete(path, body, access_token: session.access_token) })
      end

      def replace_items(session, id, uris)
        Response.build(with_items_path_fallback(id) { |path| client.put(path, { uris: }, access_token: session.access_token) })
      end

      # items_path / create のパス記憶をリセットする。テストの teardown 用。
      def reset_items_path!
        @items_path = nil
        @create_path_style = nil
      end

      # テスト間で注入した Client が漏れないよう、teardown で必ず呼ぶこと。
      def reset_client!
        @client = nil
      end

      private

      def client
        @client ||= Client.new
      end

      # items_path（tracks / items）を解決してリクエストを実行する共通処理。
      #
      # 2026年2月に /playlists/{id}/tracks → /playlists/{id}/items へのリネームが
      # 告知されたが、2026年3月9日に既存インテグレーション向けの適用は延期された。
      # 2026-07時点でどちらが有効かは未検証（Spotify のクォータ枯渇のため実APIで
      # 確認できていない）。既定は動作実績のある 'tracks'
      # （SpotifyApi.config.playlist_items_path、ENV で /items に切替可）とし、
      # 既定パスが NotFoundError を返した場合に限り、もう一方のパスへ1回だけ
      # フォールバックする。成功したパスはプロセス内に記憶し、以降はそちらを使う。
      #
      # フォールバックするのは NotFoundError のときだけ。429 / 401 / 5xx で
      # フォールバックすると、レート制限中に同じリクエストを2倍撃つことになるため、
      # それ以外の例外はそのまま伝播させる。
      def with_items_path_fallback(id)
        path = items_path
        yield(build_items_path(id, path))
      rescue NotFoundError
        alternate = alternate_items_path(path)
        Rails.logger.warn("SpotifyApi::Playlist: '#{path}' returned 404, falling back to '#{alternate}'")
        result = yield(build_items_path(id, alternate))
        @items_path = alternate
        result
      end

      def items_path
        @items_path ||= SpotifyApi.config.playlist_items_path
      end

      def alternate_items_path(path)
        path == 'tracks' ? 'items' : 'tracks'
      end

      def build_items_path(id, path)
        "playlists/#{id}/#{path}"
      end

      # POST /users/{user_id}/playlists は廃止告知済みで、後継は POST /me/playlists。
      # 既定は me/playlists とし、NotFoundError のときだけ廃止予定のパスへ1回だけ
      # フォールバックする（未移行の環境向けの保険）。以降どちらを使うかはスタイル
      # （:me / :user）だけを記憶し、パス自体は毎回 session から組み立てる
      # （ユーザーIDまで記憶すると、次に別ユーザーのセッションで呼ばれたときに
      # 誤ったユーザーIDのパスを使ってしまうため）。
      def request_create(session, body)
        path = create_path_for(session)
        client.post(path, body, access_token: session.access_token)
      rescue NotFoundError
        raise if create_path_style == :user

        alternate = "users/#{session.spotify_user_id}/playlists"
        Rails.logger.warn("SpotifyApi::Playlist: '#{path}' returned 404, falling back to '#{alternate}'")
        result = client.post(alternate, body, access_token: session.access_token)
        @create_path_style = :user
        result
      end

      def create_path_for(session)
        create_path_style == :user ? "users/#{session.spotify_user_id}/playlists" : 'me/playlists'
      end

      def create_path_style
        @create_path_style ||= :me
      end

      # ページングを最終ページまで自動で辿り、Response の配列として返す。
      #
      # Page#last_page? を基本の終了条件としつつ、取得済み件数が total に達したら
      # 止める。ページを取得しても items が空だった場合も止める（total が信頼できない
      # レスポンスへの保険）。MAX_PAGES は上記に加えた安全弁（クラスコメント参照）。
      def fetch_all(limit:)
        results = []
        offset = 0
        page_count = 0

        loop do
          page_count += 1
          if page_count > MAX_PAGES
            Rails.logger.error("SpotifyApi::Playlist: aborted pagination after #{MAX_PAGES} pages (safety valve)")
            break
          end

          page = yield(offset)
          results.concat(page.items)

          break if page.items.empty?
          break if page.last_page?
          break if page.total && results.size >= page.total

          offset += limit
        end

        results
      end
    end
  end
end
