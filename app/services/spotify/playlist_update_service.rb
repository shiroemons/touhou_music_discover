# frozen_string_literal: true

module Spotify
  # Spotifyの原曲別プレイリストを更新するサービス
  #
  # 進捗情報はRedisに保存され、フロントエンドからポーリングで取得される。
  # Redis更新はバッチ処理で最適化されている。
  class PlaylistUpdateService
    LIMIT = 50
    # 進捗情報をRedisに書き込む間隔（曲数）
    PROGRESS_UPDATE_INTERVAL = 5

    class << self
      def call(...)
        new(...).call
      end
    end

    def initialize(update_type:, spotify_session:, user_id:)
      @update_type = update_type
      @spotify_session = spotify_session
      @user_id = user_id
      @redis = RedisPool.get
      @progress_key = "playlist_update:#{user_id}"
      @playlists_cache = nil
      @failed_count = 0
      @last_error_message = nil
      @progress_info = load_progress_info
    end

    def call
      originals = fetch_originals
      return if originals.empty?

      total_count = count_total_songs(originals)
      update_progress(total: total_count)

      # プレイリスト一覧は曲ごとに遅延ロードせず、ここで一度だけ取得する。
      # 遅延ロードだと GET /me/playlists が恒常的に失敗したときに全曲分リトライを繰り返し、
      # 何も書き込めないまま completed として報告してしまう。ここで失敗させて run 全体を error にする。
      load_playlists_cache
      process_originals(originals)

      mark_completed(total_count)
    rescue StandardError => e
      Rails.logger.error("プレイリスト更新エラー: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      mark_error(e.message)
      raise
    end

    private

    attr_reader :update_type, :spotify_session, :user_id, :redis, :progress_key, :progress_info

    def load_progress_info
      data = redis.get(progress_key)
      return {} unless data

      JSON.parse(data)
    end

    def fetch_originals
      scope = case update_type
              when 'windows'
                Original.windows
              when 'pc98'
                Original.pc98
              when 'zuns_music_collection'
                Original.zuns_music_collection
              when 'akyus_untouched_score'
                Original.akyus_untouched_score
              when 'commercial_books'
                Original.commercial_books
              else
                return []
              end

      scope.includes(:original_songs)
    end

    def count_total_songs(originals)
      originals.sum { |original| original.original_songs.count { |song| !song.is_duplicate } }
    end

    def process_originals(originals)
      current_count = 0

      originals.each do |original|
        songs_in_original = original.original_songs.count { |song| !song.is_duplicate }

        update_progress(
          current_original: original.title,
          songs_in_original: songs_in_original
        )

        original.original_songs.each do |original_song|
          next if original_song.is_duplicate

          current_count = process_original_song(original_song, current_count)
        end
      end
    end

    def process_original_song(original_song, current_count)
      # spotify_tracks は has_many :through の CollectionProxy なので、そのまま扱うと
      # empty? / size / map がそれぞれ別のクエリを別の時点で発行する。空判定と
      # PlaylistTrackWriter の間には find_or_create_playlist のネットワーク I/O が挟まるため、
      # その間に SpotifyTrack が消えると writer だけが空集合を見て全消し PUT を撃つ。
      # ここで一度だけ配列に実体化し、以降の判定と書き込みが同じ集合を見るようにする。
      spotify_tracks = original_song.spotify_tracks.to_a
      return current_count if spotify_tracks.empty?

      update_progress(
        current_song: original_song.title,
        current: current_count,
        arrangement_count: spotify_tracks.size
      )

      update_playlist_for_song(original_song, spotify_tracks)

      current_count + 1
    rescue SpotifyApi::QuotaExceededError
      # クォータ超過は待っても回復しないため、握りつぶさず処理全体を止める。
      raise
    rescue StandardError => e
      # 1曲の失敗で全体は止めないが、握りつぶすと全曲失敗しても completed と報告されてしまう。
      # 失敗数と直近のエラーを記録し、mark_completed で進捗情報に残す。
      Rails.logger.error("Error processing song #{original_song.title}: #{e.class} - #{e.message}")
      @failed_count += 1
      @last_error_message = "#{e.class}: #{e.message}"
      current_count + 1
    end

    # spotify_tracks が空のまま PlaylistTrackWriter を呼ぶと PUT {"uris": []} が飛び、
    # 既存プレイリストを全消しする破壊的操作になる。渡される配列は呼び出し元
    # (process_original_song) が空判定より前に実体化済みなので、writer が別集合を
    # 見ることはない。このメソッドを他の経路から呼ばないこと。
    def update_playlist_for_song(original_song, spotify_tracks)
      playlist = find_or_create_playlist(original_song.title)
      # id が無いレスポンスをそのまま渡すと playlists//tracks へ PUT してしまう。
      return unless playlist&.[]('id')

      PlaylistTrackWriter.call(session: spotify_session, playlist_id: playlist['id'],
                               spotify_tracks:,
                               source: 'Spotify::PlaylistUpdateService')
    end

    # 作成直後に GET /playlists/{id} で取り直していたが、
    # POST /me/playlists のレスポンスがそのまま使えるため 1 往復を削る。
    def find_or_create_playlist(title)
      playlist = find_playlist(title)
      return playlist if playlist

      # POST /me/playlists は非冪等で、成功後にレスポンスがタイムアウトすると同名の空プレイリストが
      # 増えるため、リトライしない。
      created = SpotifyRetry.with_retry(source: 'Spotify::PlaylistUpdateService#create_playlist', tries: 1) do
        SpotifyApi::Playlist.create(spotify_session, name: title)
      end

      # OriginalSong.title の一意性は DB 制約で保証されていないため、作成したものも
      # キャッシュに載せて同一実行内での二重作成を防ぐ。
      @playlists_cache << created if created
      created
    end

    def find_playlist(playlist_name)
      @playlists_cache.find { |playlist| playlist['name'] == playlist_name }
    end

    # GET /me/playlists はまれに items に null 要素を含めて返すため、compact してから扱う
    # （nil['name'] は NoMethodError になる）。
    #
    # /me/playlists にはフォロー中や共同編集のプレイリストも含まれるため、
    # 「一覧に出る」ことは「自分が所有している」ことを意味しない。owner.id で絞らないと、
    # find_playlist が他人所有の同名プレイリストを「既存プレイリスト」として誤認し、
    # 自分用のプレイリストを作らないまま書き込みが 403 で永久に失敗し続ける。
    #
    # Thread.new の中から呼ばれるバックグラウンド処理なので、SpotifyRetry は既定値
    # （tries: 5, max_retry_after: 900）のまま使う。待たせる相手が居ないため、
    # index や sync_single のように早く諦める必要が無い。
    def load_playlists_cache
      fetched = SpotifyRetry.with_retry(source: 'Spotify::PlaylistUpdateService#load_playlists') do
        SpotifyApi::Playlist.all_mine(spotify_session, limit: LIMIT).compact
      end

      @playlists_cache = fetched.select { |p| p.dig('owner', 'id') == spotify_session.spotify_user_id }
    end

    # 進捗情報をメモリ上で更新し、一定間隔でRedisに書き込む
    def update_progress(**attrs)
      @progress_info.merge!(attrs.transform_keys(&:to_s))
      @pending_update_count ||= 0
      @pending_update_count += 1

      # 一定間隔またはマイルストーン（原作変更）でRedisに書き込む
      should_flush = @pending_update_count >= PROGRESS_UPDATE_INTERVAL ||
                     attrs.key?(:current_original) ||
                     attrs.key?(:total)

      flush_progress if should_flush
    end

    def flush_progress
      redis.set(progress_key, @progress_info.to_json)
      @pending_update_count = 0
    end

    def mark_completed(total_count)
      @progress_info['status'] = 'completed'
      @progress_info['completed_at'] = Time.current.to_s
      @progress_info['current'] = total_count
      # 完了扱いでも実際には書けていない曲がありうるため、失敗の実態を進捗情報に残す。
      @progress_info['failed_count'] = @failed_count
      @progress_info['last_error_message'] = @last_error_message if @last_error_message
      flush_progress
    end

    def mark_error(message)
      @progress_info['status'] = 'error'
      @progress_info['error_message'] = message
      flush_progress
    end
  end
end
