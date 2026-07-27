# frozen_string_literal: true

module SpotifyClient
  class Album
    LIMIT = 50
    SEARCH_LIMIT = 10
    JAN_SEARCH_LIMIT = 10
    DEFAULT_JAN_SEARCH_SLEEP = 1
    DEFAULT_RATE_LIMIT_MAX_WAIT = 60
    KEYWORD = 'label:東方同人音楽流通'

    def self.fetch_touhou_albums(progress_callback: nil)
      years = (2000..Time.zone.today.year).to_a
      processed_count = 0
      progress_callback&.call(
        current: processed_count,
        total: years.size,
        message: 'Spotify アルバムを取得しています',
        reset: true
      )

      finish_callback = lambda do |year, _index, _result|
        processed_count += 1
        progress_callback&.call(
          current: processed_count,
          total: years.size,
          message: "Spotify アルバムを処理しています: #{year}年 (#{processed_count}/#{years.size})"
        )
      end

      # NOTE: このブロックは ParallelRunner (Parallel) の子プロセス内で実行される。そのため
      # SpotifyRetry.with_retry 内の SpotifyRateLimit.record! は子プロセスの Rails.cache に書き込まれる。
      # 本番環境 (Redis) では親プロセスと共有されるが、開発環境 (memory_store) では共有されない。
      # これは元々の挙動と同じであり、今回の変更によるリグレッションではない。
      ParallelRunner.each(years, workers: :spotify, finish: finish_callback) do |year|
        keyword = "#{KEYWORD} year:#{year}"
        # 全カタログ取得の処理であり、年単位でスキップするとアルバムが欠落してしまうため、
        # デフォルト(tries: 5)より大きいリトライ回数を明示的に指定する。
        # ただし旧実装(429を無限リトライしていた)と異なり上限は設けてあり、
        # 1回あたりの待機時間も SpotifyRetry の max_retry_after (900秒) で頭打ちになる。
        SpotifyRetry.with_retry(source: 'SpotifyClient::Album.fetch_touhou_albums', tries: 10) do |attempt, exception|
          puts "Retrying year:#{year} (attempt #{attempt}) after #{exception.class}: #{exception.message}" if attempt.positive?

          search_and_save_albums(keyword, year)
        end
      rescue StandardError => e
        puts "Max retries reached for year:#{year}. Skipping... (#{e.class}: #{e.message})"
      end
    end

    def self.search_and_save_albums(keyword, year)
      backend.search_and_save_albums(keyword, year)
    end

    def self.process_album(s_album)
      backend.process_album(s_album)
    end

    def self.save_tracks(spotify_album, s_tracks)
      s_tracks.each do |s_track|
        SpotifyTrack.save_track(spotify_album, s_track)
      end
    end

    def self.fetch_missing_albums_by_apple_music_jan(
      max_retry_after: DEFAULT_RATE_LIMIT_MAX_WAIT,
      sleep_interval: DEFAULT_JAN_SEARCH_SLEEP,
      logger: Rails.logger,
      progress_callback: nil
    )
      result = {
        total: missing_spotify_albums_with_apple_music.count,
        processed: 0,
        created: 0,
        skipped: 0,
        missing: 0,
        errors: 0,
        rate_limited: false,
        retry_after: nil
      }

      missing_spotify_albums_with_apple_music.find_each do |album|
        if SpotifyAlbum.unscoped.exists?(album_id: album.id)
          result[:skipped] += 1
          record_jan_search_progress(result, album, progress_callback)
          next
        end

        begin
          status = with_spotify_retry(max_retry_after:) do
            search_and_save_album_by_jan(album, logger:)
          end

          result[status] += 1
        rescue *SpotifyRetry::RATE_LIMIT_ERRORS => e
          retry_after = retry_after_seconds(e)
          SpotifyRateLimit.record!(retry_after:, source: 'SpotifyClient::Album.fetch_missing_albums_by_apple_music_jan')
          result[:rate_limited] = true
          result[:retry_after] = retry_after
          logger.warn "Spotify API rate limited while searching JAN #{album.jan_code}. Retry-After: #{retry_after || 'unknown'} seconds"
          break
        rescue StandardError => e
          result[:errors] += 1
          logger.error "Spotify JAN search failed for JAN #{album.jan_code}: #{e.class}: #{e.message}"
        ensure
          record_jan_search_progress(result, album, progress_callback)
        end

        sleep sleep_interval if sleep_interval.to_f.positive?
      end

      result
    end

    def self.update_albums(spotify_albums)
      backend.update_albums(spotify_albums)
    end

    def self.fetch_and_process_album(spotify_id)
      backend.fetch_and_process_album(spotify_id)
    end

    def self.missing_spotify_albums_with_apple_music
      ::Album.joins(:apple_music_album)
             .where.missing(:spotify_albums)
             .includes(:apple_music_album)
    end
    private_class_method :missing_spotify_albums_with_apple_music

    def self.search_and_save_album_by_jan(album, logger:)
      backend.search_and_save_album_by_jan(album, logger:)
    end
    private_class_method :search_and_save_album_by_jan

    def self.with_spotify_retry(max_retry_after:, max_attempts: 3, &)
      SpotifyRetry.with_retry(source: 'SpotifyClient::Album.with_spotify_retry', tries: max_attempts, max_retry_after:, &)
    end
    private_class_method :with_spotify_retry

    def self.retry_after_seconds(error)
      SpotifyRateLimit.retry_after_seconds(error)
    end
    private_class_method :retry_after_seconds

    def self.record_jan_search_progress(result, album, progress_callback)
      result[:processed] += 1
      progress_callback&.call(result, album)
    end
    private_class_method :record_jan_search_progress

    # NOTE: バックエンドはクラスそのものを返す（インスタンス化しない）。
    #       全メソッドはクラスメソッドとして実装されている。
    def self.backend
      NativeBackend
    end
    private_class_method :backend
  end
end
