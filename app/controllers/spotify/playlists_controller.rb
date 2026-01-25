# frozen_string_literal: true

module Spotify
  class PlaylistsController < ApplicationController
    LIMIT = 50
    MAX_RETRIES = 3
    CACHE_TTL = 3.hours.to_i

    def index
      redirect_to root_url unless session[:user_id]

      redis = RedisPool.get
      auth_hash = JSON.parse(redis.get(session[:user_id]))
      @spotify_user = RSpotify::User.new(auth_hash)

      @from_cache = false
      @error = nil

      # DBキャッシュを確認
      db_playlists = SpotifyPlaylist.for_user(@spotify_user.id)
      if db_playlists.exists?
        @playlists = db_playlists.order(:position).map do |playlist|
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

      # DBにデータがない場合はSpotify APIから取得
      @playlists = fetch_playlists_from_spotify(@spotify_user)
      return if @error.present?

      # 原曲名と一致するプレイリストのみ抽出するための処理
      original_song_titles = OriginalSong.distinct.pluck(:title)
      @playlists = @playlists.select { |p| p[:name].in?(original_song_titles) }

      # DBに保存
      save_playlists_to_db(@spotify_user.id, @playlists) if @playlists.present?
    end

    def clear_cache
      redirect_to root_url unless session[:user_id]

      redis = RedisPool.get
      auth_hash = JSON.parse(redis.get(session[:user_id]))
      spotify_user = RSpotify::User.new(auth_hash)

      # DBキャッシュをクリア
      SpotifyPlaylist.for_user(spotify_user.id).delete_all

      redirect_to spotify_playlists_path
    end

    def sync_single
      redirect_to root_url unless session[:user_id]

      redis = RedisPool.get
      auth_hash = JSON.parse(redis.get(session[:user_id]))
      spotify_user = RSpotify::User.new(auth_hash)

      playlist_id = params[:id]
      playlist_name = params[:name]

      # ユーザーのプレイリストから対象を検索（認証コンテキストを保持するため）
      playlist = find_user_playlist(spotify_user, playlist_id)
      if playlist.nil?
        redirect_to spotify_playlists_path, alert: "プレイリストが見つかりません: #{playlist_name}"
        return
      end

      # 原曲を名前で検索
      original_song = OriginalSong.find_by(title: playlist_name, is_duplicate: false)

      if original_song.nil?
        redirect_to spotify_playlists_path, alert: "原曲が見つかりません: #{playlist_name}"
        return
      end

      # through関連の複雑さを避けるため直接SQL
      spotify_tracks = SpotifyTrack.find_by_sql([<<~SQL.squish, original_song.code])
        SELECT spotify_tracks.*
        FROM spotify_tracks
        INNER JOIN tracks ON tracks.id = spotify_tracks.track_id
        INNER JOIN tracks_original_songs ON tracks_original_songs.track_id = tracks.id
        WHERE tracks_original_songs.original_song_code = ?
      SQL
      if spotify_tracks.empty?
        redirect_to spotify_playlists_path, alert: 'Spotifyトラックが見つかりません'
        return
      end

      # クリアしてトラックを追加
      loop do
        tracks = playlist.tracks
        break if tracks.empty?

        playlist.remove_tracks!(tracks)
      end

      spotify_track_ids = spotify_tracks.map(&:spotify_id)
      spotify_track_ids.each_slice(50) do |ids|
        tracks = RSpotify::Track.find(ids)
        playlist.add_tracks!(tracks) if tracks.any?
      end

      # SpotifyPlaylistレコードを更新
      spotify_playlist = SpotifyPlaylist.find_by(spotify_id: playlist_id)
      spotify_playlist&.update(total: spotify_tracks.size, synced_at: Time.current)

      redirect_to spotify_playlists_path, notice: "#{playlist_name}を同期しました（#{spotify_tracks.size}曲）"
    rescue StandardError => e
      Rails.logger.error "sync_single error: #{e.class} - #{e.message}"
      redirect_to spotify_playlists_path, alert: "同期エラー: #{e.message}"
    end

    def create
      redirect_to root_url unless session[:user_id]

      redis = RedisPool.get
      auth_hash = JSON.parse(redis.get(session[:user_id]))
      spotify_user = RSpotify::User.new(auth_hash)

      update_type = params[:update_type]

      if update_type.present?
        # 進捗状況をRedisに保存するためのキー
        progress_key = "playlist_update:#{session[:user_id]}"

        # 更新処理開始前にRedisを初期化
        update_info = {
          update_type: update_type,
          total: 0,
          current: 0,
          current_song: '',
          current_original: '',
          songs_in_original: 0,
          arrangement_count: 0,
          status: 'processing',
          started_at: Time.current.to_s,
          completed_at: nil
        }
        redis.set(progress_key, update_info.to_json)

        # 非同期処理を開始（Service Objectを使用）
        user_id = session[:user_id]
        Thread.new do
          PlaylistUpdateService.call(
            update_type: update_type,
            spotify_user: spotify_user,
            user_id: user_id
          )
        rescue StandardError => e
          Rails.logger.error("プレイリスト更新エラー: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))
          redis_conn = RedisPool.get
          error_info = JSON.parse(redis_conn.get(progress_key))
          error_info['status'] = 'error'
          error_info['error_message'] = e.message
          redis_conn.set(progress_key, error_info.to_json)
        ensure
          ActiveRecord::Base.connection_pool.release_connection
        end

        # 進捗確認ページにリダイレクト
        redirect_to spotify_playlists_progress_path
      else
        # 一覧表示にリダイレクト
        redirect_to spotify_playlists_path
      end
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
      redirect_to root_url unless session[:user_id]

      redis = RedisPool.get
      auth_hash = JSON.parse(redis.get(session[:user_id]))
      spotify_user = RSpotify::User.new(auth_hash)

      # 進捗状況をRedisに保存するためのキー
      progress_key = "refresh_counts:#{session[:user_id]}"

      # 更新処理開始前にRedisを初期化
      update_info = {
        total: 0,
        current: 0,
        current_playlist: '',
        status: 'processing',
        started_at: Time.current.to_s,
        completed_at: nil
      }
      redis.set(progress_key, update_info.to_json)

      # 非同期処理を開始
      spotify_user_id = spotify_user.id
      Thread.new do
        redis_conn = RedisPool.get
        begin
          # Spotify APIから全プレイリストを取得
          playlists = []
          offset = 0
          retry_count = 0

          loop do
            fetched = spotify_user.playlists(limit: LIMIT, offset: offset)
            break if fetched.empty?

            playlists.concat(fetched)
            offset += LIMIT
            break if fetched.count < LIMIT

            sleep 0.5
          rescue RestClient::TooManyRequests
            retry_count += 1
            break unless retry_count <= MAX_RETRIES

            wait_time = 2**retry_count
            sleep wait_time
            retry
          end

          # 原曲名と一致するプレイリストのみ抽出
          original_song_titles = OriginalSong.distinct.pluck(:title)
          filtered_playlists = playlists.select { |p| p.name.in?(original_song_titles) }

          total = filtered_playlists.size
          update_info = JSON.parse(redis_conn.get(progress_key))
          update_info['total'] = total
          redis_conn.set(progress_key, update_info.to_json)

          # 各プレイリストのトラック数を更新
          filtered_playlists.each_with_index do |playlist, index|
            update_info = JSON.parse(redis_conn.get(progress_key))
            update_info['current'] = index + 1
            update_info['current_playlist'] = playlist.name
            redis_conn.set(progress_key, update_info.to_json)

            # DBレコードを更新（存在しなければ作成）
            spotify_playlist = SpotifyPlaylist.find_or_initialize_by(spotify_id: playlist.id)
            spotify_playlist.update(
              spotify_user_id: spotify_user_id,
              name: playlist.name,
              total: playlist.total,
              followers: playlist.followers['total'] || 0,
              spotify_url: playlist.external_urls['spotify'],
              original_song_code: find_original_song_code(playlist.name),
              position: index
            )

            sleep 0.2
          end

          # 完了
          update_info = JSON.parse(redis_conn.get(progress_key))
          update_info['status'] = 'completed'
          update_info['completed_at'] = Time.current.to_s
          redis_conn.set(progress_key, update_info.to_json)
        rescue StandardError => e
          Rails.logger.error("refresh_counts error: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))
          update_info = JSON.parse(redis_conn.get(progress_key))
          update_info['status'] = 'error'
          update_info['error_message'] = e.message
          redis_conn.set(progress_key, update_info.to_json)
        ensure
          ActiveRecord::Base.connection_pool.release_connection
        end
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
      return redirect_to root_url unless session[:user_id]

      redis = RedisPool.get
      auth_hash = JSON.parse(redis.get(session[:user_id]))
      @spotify_user = RSpotify::User.new(auth_hash)

      # すべてのユーザープレイリストを取得
      @playlists ||= []
      offset = 0
      retry_count = 0
      loop do
        playlists = @spotify_user.playlists(limit: LIMIT, offset:)
        @playlists.push(*playlists)
        offset += LIMIT
        break if playlists.count < LIMIT

        sleep 1
      rescue RestClient::TooManyRequests
        retry_count += 1
        break unless retry_count <= MAX_RETRIES

        wait_time = 2**retry_count
        sleep wait_time
        retry
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
            playlist = @playlists.find { |p| p.name == song.title }
            playlist_url = playlist&.external_urls&.dig('spotify')

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
    rescue StandardError => e
      Rails.logger.error("原曲構造JSON出力エラー: #{e.message}")
      # エラー時はトップページにリダイレクト
      redirect_to root_path, alert: "エラーが発生しました: #{e.message}"
    end

    private

    def find_user_playlist(spotify_user, playlist_id)
      offset = 0
      loop do
        playlists = spotify_user.playlists(limit: LIMIT, offset: offset)
        break if playlists.empty?

        found = playlists.find { |p| p.id == playlist_id }
        return found if found

        offset += LIMIT
        break if playlists.count < LIMIT

        sleep 0.5
      end
      nil
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

      # 処理時間を計算
      return unless @update_info['started_at'].present? && @update_info['completed_at'].present?

      started_at = Time.zone.parse(@update_info['started_at'])
      completed_at = Time.zone.parse(@update_info['completed_at'])
      @processing_time = (completed_at - started_at).to_i
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

    def fetch_playlists_from_spotify(spotify_user)
      playlists = []
      offset = 0
      retry_count = 0

      loop do
        fetched = spotify_user.playlists(limit: LIMIT, offset: offset)

        fetched.each do |playlist|
          followers = begin
            playlist.followers['total']
          rescue StandardError
            0
          end
          total_tracks = begin
            playlist.total
          rescue StandardError
            0
          end

          safe_playlist = {
            id: playlist.id,
            name: playlist.name,
            external_urls: playlist.external_urls,
            followers: followers,
            total: total_tracks,
            synced_at: nil
          }

          playlists << safe_playlist
        rescue StandardError => e
          Rails.logger.error("プレイリスト情報取得エラー: #{e.message}")
          next
        end

        offset += LIMIT
        break if fetched.count < LIMIT

        sleep 1
      rescue RestClient::TooManyRequests => e
        retry_count += 1

        Rails.logger.error("APIレート制限エラー詳細: ステータスコード=#{e.http_code}, ヘッダー=#{e.http_headers.inspect}")
        Rails.logger.error("レスポンス本文: #{e.http_body}") if e.respond_to?(:http_body)

        retry_after = e.respond_to?(:http_headers) && e.http_headers[:retry_after].to_i
        if retry_after && retry_after > 60
          Rails.logger.error("APIレート制限の待機時間が長すぎます: #{retry_after}秒")
          formatted_time = format_seconds(retry_after)
          @error = "Spotify APIのレート制限に達しました。サーバーが #{formatted_time} の待機を要求しています。"
          break
        end

        if retry_count <= MAX_RETRIES
          wait_time = 2**retry_count
          Rails.logger.warn("APIレート制限到達: #{wait_time}秒待機してリトライします (#{retry_count}/#{MAX_RETRIES})")
          sleep wait_time
          retry
        else
          Rails.logger.error('APIレート制限エラー: 最大リトライ回数に達しました')
          @error = 'Spotify APIのレート制限に達しました。しばらく時間をおいて再度お試しください。'
          break
        end
      rescue StandardError => e
        Rails.logger.error("プレイリスト取得エラー: #{e.message}")
        @error = "プレイリスト情報の取得中にエラーが発生しました: #{e.message}"
        break
      end

      playlists.reverse!
      playlists
    end

    def save_playlists_to_db(spotify_user_id, playlists)
      playlists.each_with_index do |playlist, index|
        SpotifyPlaylist.find_or_create_by(spotify_id: playlist[:id]) do |p|
          p.spotify_user_id = spotify_user_id
          p.name = playlist[:name]
          p.total = playlist[:total]
          p.followers = playlist[:followers]
          p.spotify_url = playlist[:external_urls][:spotify] || playlist[:external_urls]['spotify']
          p.original_song_code = find_original_song_code(playlist[:name])
          p.position = index
        end
      end
    end

    def find_original_song_code(playlist_name)
      # プレイリスト名から原曲コードを検索
      original_song = OriginalSong.find_by(title: playlist_name, is_duplicate: false)
      original_song&.code
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
