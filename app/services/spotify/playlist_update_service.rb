# frozen_string_literal: true

module Spotify
  # Spotifyの原曲別プレイリストを更新するサービス
  #
  # 進捗情報はRedisに保存され、フロントエンドからポーリングで取得される。
  # Redis更新はバッチ処理で最適化されている。
  class PlaylistUpdateService
    LIMIT = 50
    MAX_RETRIES = 3
    # 進捗情報をRedisに書き込む間隔（曲数）
    PROGRESS_UPDATE_INTERVAL = 5

    class << self
      def call(...)
        new(...).call
      end
    end

    def initialize(update_type:, spotify_user:, user_id:)
      @update_type = update_type
      @spotify_user = spotify_user
      @user_id = user_id
      @redis = RedisPool.get
      @progress_key = "playlist_update:#{user_id}"
      @playlists_cache = []
      @progress_info = load_progress_info
    end

    def call
      originals = fetch_originals
      return if originals.empty?

      total_count = count_total_songs(originals)
      update_progress(total: total_count)

      process_originals(originals)

      mark_completed(total_count)
    rescue StandardError => e
      Rails.logger.error("プレイリスト更新エラー: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      mark_error(e.message)
      raise
    end

    private

    attr_reader :update_type, :spotify_user, :user_id, :redis, :progress_key, :progress_info

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
      spotify_tracks = original_song.spotify_tracks
      return current_count if spotify_tracks.empty?

      update_progress(
        current_song: original_song.title,
        current: current_count,
        arrangement_count: spotify_tracks.size
      )

      update_playlist_for_song(original_song, spotify_tracks)

      current_count + 1
    rescue OpenSSL::SSL::SSLError => e
      handle_ssl_error(e, original_song)
      current_count + 1
    rescue RestClient::TooManyRequests => e
      handle_rate_limit_error(e)
      current_count + 1
    rescue StandardError => e
      Rails.logger.error("Error processing song #{original_song.title}: #{e.message}")
      current_count + 1
    end

    def update_playlist_for_song(original_song, spotify_tracks)
      playlist = find_or_create_playlist(original_song.title)
      return unless playlist

      clear_playlist_tracks(playlist)
      add_tracks_to_playlist(playlist, spotify_tracks)
    end

    def find_or_create_playlist(title)
      playlist = find_playlist(title)

      if playlist.nil?
        new_playlist = spotify_user.create_playlist!(title)
        playlist = RSpotify::Playlist.find_by_id(new_playlist.id)
      end

      playlist
    end

    def find_playlist(playlist_name)
      load_playlists_cache if @playlists_cache.empty?

      @playlists_cache.find do |p|
        if p.is_a?(Hash) || p.is_a?(ActiveSupport::HashWithIndifferentAccess)
          p[:name] == playlist_name
        else
          p.name == playlist_name
        end
      end
    end

    def load_playlists_cache
      offset = 0

      loop do
        playlists = spotify_user.playlists(limit: LIMIT, offset: offset)
        @playlists_cache.push(*playlists)
        offset += LIMIT
        break if playlists.count < LIMIT

        sleep 1
      rescue RestClient::TooManyRequests => e
        rate_limit_retry_allowed?(e) || break
      end
    end

    def rate_limit_retry_allowed?(error)
      Rails.logger.error("APIレート制限エラー詳細: ステータスコード=#{error.http_code}")

      retry_after = error.respond_to?(:http_headers) && error.http_headers[:retry_after].to_i
      if retry_after && retry_after > 60
        Rails.logger.error("APIレート制限の待機時間が長すぎます: #{retry_after}秒")
        return false
      end

      @cache_load_retry_count ||= 0
      @cache_load_retry_count += 1

      if @cache_load_retry_count <= MAX_RETRIES
        wait_time = 2**@cache_load_retry_count
        Rails.logger.warn("APIレート制限到達: #{wait_time}秒待機してリトライします")
        sleep wait_time
        true # retry
      else
        Rails.logger.error('APIレート制限エラー: 最大リトライ回数に達しました')
        false
      end
    end

    def clear_playlist_tracks(playlist)
      loop do
        tracks = playlist.tracks
        break if tracks.empty?

        playlist.remove_tracks!(tracks)
      end
    end

    def add_tracks_to_playlist(playlist, spotify_tracks)
      spotify_track_ids = spotify_tracks.map(&:spotify_id)

      spotify_track_ids.each_slice(50) do |ids|
        tracks = RSpotify::Track.find(ids)
        playlist.add_tracks!(tracks) if tracks.any?
      end
    end

    def handle_ssl_error(error, original_song)
      Rails.logger.warn("SSL Error for #{original_song.title}: #{error.message}")

      @ssl_retry_count ||= 0
      @ssl_retry_count += 1

      if @ssl_retry_count < 3
        sleep 1
        raise error # retry via caller
      end

      @ssl_retry_count = 0
    end

    def handle_rate_limit_error(error)
      Rails.logger.error("APIレート制限エラー詳細: ステータスコード=#{error.http_code}")
      Rails.logger.error("レスポンス本文: #{error.http_body}") if error.respond_to?(:http_body)

      retry_after = error.respond_to?(:http_headers) && error.http_headers[:retry_after].to_i
      if retry_after && retry_after > 60
        formatted_time = format_seconds(retry_after)
        mark_error("APIレート制限に達しました。サーバーが #{formatted_time} の待機を要求しています。")
        return
      end

      @rate_limit_retry_count ||= 0
      @rate_limit_retry_count += 1

      if @rate_limit_retry_count <= MAX_RETRIES
        wait_time = 2**@rate_limit_retry_count
        Rails.logger.warn("APIレート制限到達: #{wait_time}秒待機してリトライします (#{@rate_limit_retry_count}/#{MAX_RETRIES})")
        sleep wait_time
        raise error # retry via caller
      else
        Rails.logger.error('APIレート制限エラー: 最大リトライ回数に達しました')
        @rate_limit_retry_count = 0
      end
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
      flush_progress
    end

    def mark_error(message)
      @progress_info['status'] = 'error'
      @progress_info['error_message'] = message
      flush_progress
    end

    def format_seconds(seconds)
      hours = seconds / 3600
      minutes = (seconds % 3600) / 60
      remaining_seconds = seconds % 60

      if hours.positive?
        "#{hours}時間#{minutes}分#{remaining_seconds}秒（#{seconds}秒）"
      elsif minutes.positive?
        "#{minutes}分#{remaining_seconds}秒（#{seconds}秒）"
      else
        "#{seconds}秒"
      end
    end
  end
end
