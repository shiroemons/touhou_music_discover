# frozen_string_literal: true

module Spotify
  class PlaylistsController < ApplicationController
    include SpotifyAuthentication

    LIMIT = 50

    # PlaylistUpdateService#fetch_originals が受け付ける update_type の一覧。
    # 未知の値を渡すと fetch_originals が [] を返して call が mark_completed 抜きで
    # 早期リターンするため、progress_key が 'processing' のまま止まってしまう。
    # ここで事前に弾き、Redis へ書き込む前にリダイレクトする。
    VALID_UPDATE_TYPES = %w[windows pc98 zuns_music_collection akyus_untouched_score commercial_books].freeze

    before_action :require_spotify_session,
                  only: %i[index clear_cache sync_single create refresh_counts original_songs]

    def index
      @from_cache = false
      @error = nil

      db_playlists = SpotifyPlaylist.for_user(spotify_user_id)
      if db_playlists.exists?
        # position は fetch_playlists_from_spotify が API 順を反転してから振っているため、
        # position 0 が最も古く作成されたプレイリスト = 原曲順の先頭（赤より紅い夢）になる。
        # 昇順で並べると画面が原曲順になる。
        @playlists = db_playlists.order(position: :asc).map do |playlist|
          {
            id: playlist.spotify_id,
            name: playlist.name,
            external_urls: { spotify: playlist.spotify_url },
            followers: playlist.followers,
            total: playlist.total,
            synced_at: playlist.synced_at
          }
        end
        @from_cache = true
        return
      end

      @playlists = fetch_playlists_from_spotify
      return if @error.present?

      save_playlists_to_db(spotify_user_id, @playlists) if @playlists.present?
    end

    def clear_cache
      SpotifyPlaylist.for_user(spotify_user_id).delete_all

      redirect_to spotify_playlists_path
    end

    def sync_single
      playlist_id = params[:id]
      playlist_name = params[:name]

      # このアプリが書き込んでよいのは原曲名のプレイリストだけ。
      # playlist_id は外部から渡されるため、破壊的操作の前にサーバ側で必ず検証する。
      # ここで必要なのは original_song.code だけなので、レコードそのものではなく
      # playlist_code_for で直接コードを引く。
      original_song_code = OriginalSong.playlist_code_for(playlist_name)
      if original_song_code.nil?
        redirect_to spotify_playlists_path,
                    alert: I18n.t('spotify.playlists.alerts.original_song_not_found', name: playlist_name)
        return
      end

      # id がユーザー自身のプレイリストであり、かつ実際の名前が原曲名と一致することを確認する。
      playlist = find_user_playlist(playlist_id, playlist_name)
      if playlist.nil?
        redirect_to spotify_playlists_path,
                    alert: I18n.t('spotify.playlists.alerts.playlist_not_found', name: playlist_name)
        return
      end

      # through関連の複雑さを避けるため直接SQL
      spotify_tracks = SpotifyTrack.find_by_sql([<<~SQL.squish, original_song_code])
        SELECT spotify_tracks.*
        FROM spotify_tracks
        INNER JOIN tracks ON tracks.id = spotify_tracks.track_id
        INNER JOIN tracks_original_songs ON tracks_original_songs.track_id = tracks.id
        WHERE tracks_original_songs.original_song_code = ?
      SQL
      if spotify_tracks.empty?
        redirect_to spotify_playlists_path, alert: I18n.t('spotify.playlists.alerts.tracks_not_found')
        return
      end

      # 対話的なリクエスト（ユーザーが同期ボタンを押して待っている）なので、
      # レート制限時は長く待たず早めに諦める。デフォルト（tries: 5, max_retry_after: 900）は
      # バックグラウンド処理向け。
      Spotify::PlaylistTrackWriter.call(session: spotify_session, playlist_id:,
                                        spotify_tracks:, tries: 3, max_retry_after: 60,
                                        source: 'Spotify::PlaylistsController#sync_single')

      spotify_playlist = SpotifyPlaylist.find_by(spotify_id: playlist_id)
      spotify_playlist&.update(total: spotify_tracks.size, synced_at: Time.current)

      redirect_to spotify_playlists_path, notice: "#{playlist_name}を同期しました（#{spotify_tracks.size}曲）"
    rescue SpotifyApi::QuotaExceededError => e
      # クォータ超過は復旧まで数時間かかるため、通常のレート制限とは別メッセージにする。
      # RateLimitError のサブクラスなので RateLimitError より先に rescue する必要がある。
      Rails.logger.error("sync_single quota exceeded: #{e.message}")
      mark_sync_incomplete(params[:id])
      redirect_to spotify_playlists_path, alert: I18n.t('spotify.playlists.alerts.quota_exceeded')
    rescue SpotifyApi::RateLimitError => e
      Rails.logger.error("sync_single rate limited: #{e.message}")
      mark_sync_incomplete(params[:id])
      redirect_to spotify_playlists_path, alert: I18n.t('spotify.playlists.alerts.rate_limited')
    rescue StandardError => e
      # 例外メッセージをそのまま画面に出すと Spotify の生のエラー文が漏れるため、
      # 詳細はログに残し、利用者には次にとるべき行動だけを伝える。
      Rails.logger.error("sync_single error: #{e.class} - #{e.message}")
      mark_sync_incomplete(params[:id])
      redirect_to spotify_playlists_path, alert: I18n.t('spotify.playlists.alerts.sync_failed')
    end

    def create
      update_type = params[:update_type]

      if update_type.blank? || VALID_UPDATE_TYPES.exclude?(update_type)
        redirect_to spotify_playlists_path
        return
      end

      progress_key = "playlist_update:#{session[:user_id]}"
      redis = RedisPool.get
      redis.set(progress_key, {
        update_type:, total: 0, current: 0, current_song: '', current_original: '',
        songs_in_original: 0, arrangement_count: 0, status: 'processing',
        started_at: Time.current.to_s, completed_at: nil
      }.to_json)

      # スレッドにはリクエストのコンテキストが無いため、セッションとユーザーIDは
      # Thread.new の前にローカル変数へ取り出しておく。
      user_id = session[:user_id]
      session_for_thread = spotify_session
      Thread.new do
        # 進捗キーへの error 書き込みは PlaylistUpdateService#mark_error が行うため、
        # ここではログを残すだけにする（以前は二重に書いていた）。
        PlaylistUpdateService.call(update_type:, spotify_session: session_for_thread, user_id:)
      rescue StandardError => e
        Rails.logger.error("プレイリスト更新エラー: #{e.class} - #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
      ensure
        ActiveRecord::Base.connection_pool.release_connection
      end

      redirect_to spotify_playlists_progress_path
    end

    def progress
      load_progress_info
    end

    def progress_stream
      load_progress_info

      respond_to do |format|
        format.turbo_stream
      end
    end

    def refresh_counts
      progress_key = "refresh_counts:#{session[:user_id]}"
      RedisPool.get.set(progress_key, {
        total: 0,
        current: 0,
        current_playlist: '',
        status: 'processing',
        started_at: Time.current.to_s,
        completed_at: nil
      }.to_json)

      # スレッドにはリクエストのコンテキストが無いため、セッションとユーザーIDは
      # Thread.new の前にローカル変数へ取り出しておく。
      session_for_thread = spotify_session
      user_id_for_thread = spotify_user_id
      Thread.new do
        refresh_counts_in_background(session_for_thread, user_id_for_thread, progress_key)
      ensure
        ActiveRecord::Base.connection_pool.release_connection
      end

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace('refresh-counts-container',
                                                    partial: 'refresh_counts_progress')
        end
        format.html { redirect_to spotify_playlists_path }
      end
    end

    def refresh_counts_stream
      load_refresh_counts_info

      respond_to do |format|
        format.turbo_stream
      end
    end

    def original_songs
      # 対話的なリクエスト（ユーザーがJSONのダウンロードを待っている）なので、
      # レート制限時は長く待たず早めに諦める。デフォルト（tries: 5, max_retry_after: 900）は
      # バックグラウンド処理向け。
      #
      # GET /me/playlists はまれに items に null 要素を含めて返すため、compact してから扱う
      # （nil['name'] は NoMethodError になる）。
      @playlists = SpotifyRetry.with_retry(source: 'Spotify::PlaylistsController#original_songs',
                                           tries: 3, max_retry_after: 60) do
        SpotifyApi::Playlist.all_mine(spotify_session, limit: LIMIT).compact
      end

      # 原曲データ構造を構築
      data = {}

      # N+1を防ぐため、すべての原曲と曲を一度に取得
      Original.original_types.each_key do |type|
        originals = Original.public_send(type)
                            .includes(:original_songs)
                            .order(:series_order)

        type_data = originals.filter_map do |original|
          # メモリ上でフィルタリングして追加のクエリを防ぐ
          non_duplicated_songs = original.original_songs.reject(&:is_duplicate)
                                         .sort_by(&:track_number)

          original_songs = non_duplicated_songs.filter_map do |song|
            # プレイリストを検索
            playlist = @playlists.find { |p| p['name'] == song.title }
            playlist_url = playlist&.dig('external_urls', 'spotify')

            # プレイリストURLがある場合のみ含める
            if playlist_url
              {
                name: song.title,
                playlist_url: playlist_url
              }
            end
          end

          # original_songsが空でない場合のみ含める
          if original_songs.any?
            {
              name: original.title,
              original_songs: original_songs
            }
          end
        end

        # タイプレベルでも空でない場合のみ含める
        data[type] = type_data if type_data.any?
      end

      respond_to do |format|
        format.json do
          send_data JSON.pretty_generate(data),
                    filename: "original_songs_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json",
                    type: 'application/json',
                    disposition: 'attachment'
        end
        format.html do
          json_content = JSON.pretty_generate(data)
          send_data json_content,
                    filename: "original_songs_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json",
                    type: 'application/json',
                    disposition: 'attachment'
        end
      end
    rescue SpotifyApi::QuotaExceededError => e
      # クォータ超過は復旧まで数時間かかるため、index / sync_single と同じ専用メッセージにする。
      # RateLimitError のサブクラスなので RateLimitError より先に rescue する必要がある。
      Rails.logger.error("original_songs quota exceeded: #{e.message}")
      redirect_to root_path, alert: I18n.t('spotify.playlists.alerts.quota_exceeded')
    rescue SpotifyApi::RateLimitError => e
      Rails.logger.error("original_songs rate limited: #{e.message}")
      redirect_to root_path, alert: I18n.t('spotify.playlists.alerts.rate_limited')
    rescue StandardError => e
      Rails.logger.error("原曲構造JSON出力エラー: #{e.message}")
      # エラー時はトップページにリダイレクト
      redirect_to root_path, alert: "エラーが発生しました: #{e.message}"
    end

    private

    # 指定 id がユーザー自身のプレイリストで、かつ名前が期待値と一致する場合だけ返す。
    # 名前の一致まで見るのは、外部から渡された id で別のプレイリストを壊さないため。
    #
    # 所有確認は GET /me/playlists ではなく GET /playlists/{id} で行う。
    # /me/playlists にはフォロー中や共同編集(collaborative)のプレイリストも含まれるため、
    # 「一覧に出る」ことは「自分が所有している」ことを意味しない。原曲名と同名の
    # 共同編集プレイリストがあると、他人所有のプレイリストを丸ごと差し替えてしまう。
    # 1 リクエストで済むので、613 件を全ページ辿る必要も無くなる。
    def find_user_playlist(playlist_id, expected_name)
      # sync_single と同じく対話的なリクエストなので、レート制限時は早めに諦める。
      playlist = SpotifyRetry.with_retry(source: 'Spotify::PlaylistsController#sync_single',
                                         tries: 3, max_retry_after: 60) do
        SpotifyApi::Playlist.find(spotify_session, playlist_id)
      end

      return nil if playlist.nil?
      return nil unless playlist['name'] == expected_name

      owner_id = playlist.dig('owner', 'id')
      if owner_id != spotify_user_id
        # 他人のプレイリストへの破壊的書き込みを未然に止めた記録。運用上追跡できるようにする。
        Rails.logger.warn("sync_single rejected a playlist owned by #{owner_id.inspect}: #{playlist_id}")
        return nil
      end

      playlist
    rescue SpotifyApi::NotFoundError
      nil
    end

    # 書き込みの途中で失敗すると、PUT 済みの先頭 100 件だけが反映された状態が残りうる。
    # synced_at を落として「このプレイリストは同期途中で失敗した」ことを記録する。
    # PUT は冪等なので、再同期すれば完全に復旧できる。
    def mark_sync_incomplete(playlist_id)
      SpotifyPlaylist.find_by(spotify_id: playlist_id)&.update(synced_at: nil)
    end

    def load_progress_info
      redis = RedisPool.get
      progress_key = "playlist_update:#{session[:user_id]}"

      @update_info = redis.get(progress_key).present? ? JSON.parse(redis.get(progress_key)) : {}
      @completed = @update_info['status'] == 'completed'
      @error = @update_info['status'] == 'error'

      # 更新が完了していればメッセージを表示
      return unless @completed

      @message = case @update_info['update_type']
                 when 'windows'
                   'Windowsシリーズの原曲別プレイリストの更新が完了しました'
                 when 'pc98'
                   'PC-98シリーズの原曲別プレイリストの更新が完了しました'
                 when 'zuns_music_collection'
                   "ZUN's Music Collectionの原曲別プレイリストの更新が完了しました"
                 when 'akyus_untouched_score'
                   '幺樂団の歴史の原曲別プレイリストの更新が完了しました'
                 when 'commercial_books'
                   '商業書籍の原曲別プレイリストの更新が完了しました'
                 else
                   'プレイリストの更新が完了しました'
                 end

      # 失敗した曲は例外を握りつぶして次へ進むため、completed でも1曲も書けていないことがある。
      # 完了メッセージに失敗数を添えて、実態が伝わるようにする。
      failed = @update_info['failed_count'].to_i
      @message = "#{@message}（#{failed}曲の更新に失敗しました）" if failed.positive?

      # 処理時間を計算
      return unless @update_info['started_at'].present? && @update_info['completed_at'].present?

      started_at = Time.zone.parse(@update_info['started_at'])
      completed_at = Time.zone.parse(@update_info['completed_at'])
      @processing_time = (completed_at - started_at).to_i
    end

    # 原曲名に一致するプレイリストだけを一覧用の Hash に詰め替えて返す。
    #
    # follower 数は GET /me/playlists のレスポンスに含まれないため、以前は
    # 1 件ごとに GET /playlists/{id} が暗黙に発火していた
    # （実測で 613 件中 612 件が対象 = 一覧表示 1 回あたり
    # 625 リクエスト）。follower の最新化は明示的な「曲数を更新」ボタン
    # (refresh_counts) の責務にして、一覧では DB の既存値を表示する。
    def fetch_playlists_from_spotify
      titles = OriginalSong.playlist_titles.to_set
      code_map = OriginalSong.playlist_code_map

      # これは対話的なリクエスト（ユーザーがページの読み込みを待っている）なので、
      # レート制限時は長く待たず早めに諦めてバナー表示に切り替える。長時間待つ
      # デフォルト（tries: 5, max_retry_after: 900）はバックグラウンド処理向け。
      fetched = SpotifyRetry.with_retry(source: 'Spotify::PlaylistsController#index', tries: 3,
                                        max_retry_after: 60) do
        SpotifyApi::Playlist.all_mine(spotify_session, limit: LIMIT)
      end

      # GET /me/playlists はまれに items に null 要素を含めて返すことがあるため、
      # nil を除いてからフィルタする（nil['name'] は NoMethodError になる）。
      #
      # /me/playlists にはフォロー中や共同編集のプレイリストも含まれるため、
      # 「一覧に出る」ことは「自分が所有している」ことを意味しない。owner.id で
      # 絞らないと、他人が所有する同名プレイリストをこのユーザーの行として保存してしまう。
      matched = fetched.compact.select { |p| p.dig('owner', 'id') == spotify_user_id }
                               .select { |playlist| titles.include?(playlist['name']) }

      matched.map do |playlist|
        {
          id: playlist['id'],
          name: playlist['name'],
          external_urls: playlist['external_urls'] || {},
          # follower 数は GET /me/playlists のレスポンスに含まれない。ここは clear_cache で
          # 行を消した直後にしか到達しないため、保存済みの値も残っていない。0 で保存し、
          # 最新化は「曲数を更新」(refresh_counts) の責務とする。
          followers: 0,
          total: playlist.dig('tracks', 'total').to_i,
          synced_at: nil,
          original_song_code: code_map[playlist['name']]
        }
      end.reverse
    rescue SpotifyApi::QuotaExceededError => e
      # クォータ超過は Retry-After が数時間規模になり、通常のレート制限のように
      # 「しばらく待てば復旧する」では済まないため、別メッセージで区別する。
      # RateLimitError のサブクラスなので RateLimitError より先に rescue する必要がある。
      Rails.logger.error("Spotify APIのクォータ超過: #{e.message}")
      @error = 'Spotify API の利用枠を使い切りました。復旧まで時間がかかるため、しばらく経ってから再度お試しください。'
      []
    rescue SpotifyApi::RateLimitError => e
      Rails.logger.error("Spotify APIレート制限: #{e.message}")
      @error = 'Spotify APIのレート制限に達しました。しばらく時間をおいて再度お試しください。'
      []
    rescue SpotifyApi::Error => e
      Rails.logger.error("プレイリスト取得エラー: #{e.class} - #{e.message}")
      @error = "プレイリスト情報の取得中にエラーが発生しました: #{e.message}"
      []
    end

    # find_or_create_by のブロック内で属性を設定していたため、既存レコードが
    # 一切更新されなかった。follower / total を DB 値から表示する設計にした以上、
    # ここが更新されないと画面が古いままになる。
    def save_playlists_to_db(spotify_user_id, playlists)
      playlists.each_with_index do |playlist, index|
        record = SpotifyPlaylist.find_or_initialize_by(spotify_id: playlist[:id])
        record.spotify_user_id = spotify_user_id
        record.name = playlist[:name]
        record.total = playlist[:total]
        record.followers = playlist[:followers]
        record.spotify_url = playlist[:external_urls]['spotify'] || playlist[:external_urls][:spotify]
        record.original_song_code = playlist[:original_song_code]
        record.position = index
        record.save!
      end
    end

    # 原曲名に一致するプレイリストの total / followers / position を最新化する。
    #
    # follower 数は GET /me/playlists のレスポンスに含まれないため、1 件ごとに
    # GET /playlists/{id} が必要になる。一覧表示のたびに暗黙で払っていたこの
    # コストを、ユーザーが明示的にボタンを押したときだけ払う形にした。
    #
    # Thread.new の中から呼ばれるバックグラウンド処理なので、SpotifyRetry は
    # 既定値（tries: 5, max_retry_after: 900）のまま使う。待たせる相手が居ないため、
    # index や sync_single のように早く諦める必要が無い。
    def refresh_counts_in_background(spotify_session, spotify_user_id, progress_key)
      redis = RedisPool.get
      titles = OriginalSong.playlist_titles.to_set
      code_map = OriginalSong.playlist_code_map

      playlists = SpotifyRetry.with_retry(source: 'Spotify::PlaylistsController#refresh_counts') do
        SpotifyApi::Playlist.all_mine(spotify_session, limit: LIMIT)
      end

      # index (fetch_playlists_from_spotify) と同じ並びにしてから position を振る。
      # index は matched を reverse した順に position 0,1,2... を振り、ビューは
      # order(position: :asc) で描画する（position 0 が最も古く作成されたプレイリスト
      # = 原曲順の先頭になる）。ここで API 順のまま振ると、ボタンを押した瞬間に
      # 一覧の並びが上下反転してしまう。
      #
      # index と同じ理由で owner.id によるフィルタも必須。これが無いと、他人が所有する
      # 同名プレイリストに GET /playlists/{id} を発行してしまう（403 の原因にもなる）。
      matched = playlists.compact.select { |p| p.dig('owner', 'id') == spotify_user_id }
                                 .select { |playlist| titles.include?(playlist['name']) }.reverse

      write_refresh_progress(redis, progress_key) { |info| info['total'] = matched.size }

      matched.each_with_index do |playlist, index|
        write_refresh_progress(redis, progress_key) do |info|
          info['current'] = index + 1
          info['current_playlist'] = playlist['name']
        end

        save_refreshed_playlist(spotify_session, spotify_user_id, playlist, code_map, index)
      end

      write_refresh_progress(redis, progress_key) do |info|
        info['status'] = 'completed'
        info['completed_at'] = Time.current.to_s
      end
    rescue StandardError => e
      Rails.logger.error("refresh_counts error: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      write_refresh_progress(redis, progress_key) do |info|
        info['status'] = 'error'
        info['error_message'] = e.message
      end
    end

    def save_refreshed_playlist(spotify_session, spotify_user_id, playlist, code_map, position)
      detail = SpotifyRetry.with_retry(source: 'Spotify::PlaylistsController#refresh_counts') do
        SpotifyApi::Playlist.find(spotify_session, playlist['id'])
      end

      record = SpotifyPlaylist.find_or_initialize_by(spotify_id: playlist['id'])
      record.spotify_user_id = spotify_user_id
      record.name = playlist['name']
      record.total = detail.dig('tracks', 'total').to_i
      record.followers = detail.dig('followers', 'total').to_i
      record.spotify_url = playlist.dig('external_urls', 'spotify')
      record.original_song_code = code_map[playlist['name']]
      record.position = position
      record.save!
    end

    def write_refresh_progress(redis, progress_key)
      raw = redis.get(progress_key)
      info = raw.present? ? JSON.parse(raw) : {}
      yield(info)
      redis.set(progress_key, info.to_json)
    end

    def load_refresh_counts_info
      redis = RedisPool.get
      progress_key = "refresh_counts:#{session[:user_id]}"

      @update_info = redis.get(progress_key).present? ? JSON.parse(redis.get(progress_key)) : {}
      @completed = @update_info['status'] == 'completed'
      @error = @update_info['status'] == 'error'

      return unless @completed

      @message = 'プレイリスト曲数の更新が完了しました'

      return unless @update_info['started_at'].present? && @update_info['completed_at'].present?

      started_at = Time.zone.parse(@update_info['started_at'])
      completed_at = Time.zone.parse(@update_info['completed_at'])
      @processing_time = (completed_at - started_at).to_i
    end
  end
end
