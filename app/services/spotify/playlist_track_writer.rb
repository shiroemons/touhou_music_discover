# frozen_string_literal: true

module Spotify
  # プレイリストの中身をトラック一覧で丸ごと差し替える。
  #
  # 以前は「tracks を取得して remove を繰り返す」→「50 件ずつ add する」という
  # ループだったが、PUT /playlists/{id}/tracks が uris で中身を置き換えられるため、
  # 1 リクエスト（100 件超の分だけ追加リクエスト）に圧縮できる。
  #
  # PUT は 1 回 100 件までなので、先頭 100 件を PUT し、残りを 100 件ずつ POST で足す。
  # **PUT が後に来ると先に足した分が消える。** 順序を誤ると破壊的なので、
  # controller とサービスで実装を分けず、このクラスに閉じ込めている。
  class PlaylistTrackWriter
    MAX_ITEMS_PER_REQUEST = 100

    class << self
      def call(...)
        new(...).call
      end
    end

    # @param source [String] SpotifyRetry がレート制限を記録するときの呼び出し元名
    # @param allow_clear [Boolean] true でなければ uris が空のときに ArgumentError を送出する。
    #   PUT {"uris": []} はプレイリストの中身を全消しする破壊的操作のため、明示的な opt-in を必須にする。
    # @param tries [Integer] SpotifyRetry.with_retry に渡す最大試行回数。
    #   Task 11 のバックグラウンド呼び出しはデフォルト（SpotifyRetry::DEFAULT_TRIES）のままでよいが、
    #   sync_single のような対話的な呼び出しは短く上書きする。
    # @param max_retry_after [Integer] SpotifyRetry.with_retry に渡す待機上限秒数。tries と同様の理由で調整可能にする。
    # @return [Integer] 書き込んだトラック数
    # rubocop:disable Metrics/ParameterLists -- 呼び出し側（sync_single とバックグラウンドサービス）が
    # allow_clear/tries/max_retry_after を個別に指定できる必要があるため、
    # オプションハッシュへの集約はせずキーワード引数のまま公開する。
    def initialize(session:, playlist_id:, spotify_tracks:, source:,
                   allow_clear: false,
                   tries: SpotifyRetry::DEFAULT_TRIES,
                   max_retry_after: SpotifyRetry::DEFAULT_MAX_RETRY_AFTER)
      @session = session
      @playlist_id = playlist_id
      @uris = spotify_tracks.map { |track| "spotify:track:#{track.spotify_id}" }
      @source = source
      @allow_clear = allow_clear
      @tries = tries
      @max_retry_after = max_retry_after
    end
    # rubocop:enable Metrics/ParameterLists

    def call
      # uris が空だと PUT はプレイリストを全消しする。現在の呼び出し元はどちらも
      # 事前に空を弾いているが、将来の別の呼び出し元が同じ約束を守る保証はないため、
      # 明示的な opt-in が無い限り拒否する。
      raise ArgumentError, 'refusing to clear a playlist: pass allow_clear: true to opt in' if uris.empty? && !allow_clear

      # 空配列でも PUT する。中身を空にする(全消し)操作になる。
      with_retry { SpotifyApi::Playlist.replace_items(session, playlist_id, uris.first(MAX_ITEMS_PER_REQUEST)) }

      uris.drop(MAX_ITEMS_PER_REQUEST).each_slice(MAX_ITEMS_PER_REQUEST) do |batch|
        with_retry { SpotifyApi::Playlist.add_items(session, playlist_id, batch) }
      end

      uris.size
    end

    private

    attr_reader :session, :playlist_id, :uris, :source, :allow_clear, :tries, :max_retry_after

    def with_retry(&)
      SpotifyRetry.with_retry(source:, tries:, max_retry_after:, &)
    end
  end
end
