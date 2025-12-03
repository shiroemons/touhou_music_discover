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

      cache_key = "spotify_playlists:#{session[:user_id]}"
      @from_cache = false

      # キャッシュを確認
      cached_data = redis.get(cache_key)
      if cached_data.present?
        @playlists = JSON.parse(cached_data, symbolize_names: true)
        @from_cache = true
        @error = nil
        return
      end

      @playlists = []
      @error = nil

      begin
        # 通常のプレイリスト表示処理
        offset = 0
        retry_count = 0

        loop do
          playlists = @spotify_user.playlists(limit: LIMIT, offset:)

          # 事前にフォロワー情報とトラック数を安全に取得して保存
          playlists.each do |playlist|
            # フォロワー数とトラック数を事前に安全に取得
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

            # 必要な情報を含むハッシュを作成
            safe_playlist = {
              id: playlist.id,
              name: playlist.name,
              external_urls: playlist.external_urls,
              followers:,
              total: total_tracks
            }

            @playlists << safe_playlist
          rescue StandardError => e
            Rails.logger.error("プレイリスト情報取得エラー: #{e.message}")
            # エラーが発生しても処理を継続
            next
          end

          offset += LIMIT
          break if playlists.count < LIMIT

          # API制限に引っかからないよう、リクエスト間に少し待機
          sleep 1
        rescue RestClient::TooManyRequests => e
          retry_count += 1

          # 429エラーの詳細情報をログに出力
          Rails.logger.error("APIレート制限エラー詳細: ステータスコード=#{e.http_code}, ヘッダー=#{e.http_headers.inspect}")
          Rails.logger.error("レスポンス本文: #{e.http_body}") if e.respond_to?(:http_body)

          # Retry-Afterヘッダーの確認
          retry_after = e.respond_to?(:http_headers) && e.http_headers[:retry_after].to_i
          if retry_after && retry_after > 60
            Rails.logger.error("APIレート制限の待機時間が長すぎます: #{retry_after}秒")
            formatted_time = format_seconds(retry_after)
            @error = "Spotify APIのレート制限に達しました。サーバーが #{formatted_time} の待機を要求しています。"
            break
          end

          if retry_count <= MAX_RETRIES
            # 429エラーの場合は待機時間を増やしてリトライ
            wait_time = 2**retry_count # エクスポネンシャルバックオフ
            Rails.logger.warn("APIレート制限到達: #{wait_time}秒待機してリトライします (#{retry_count}/#{MAX_RETRIES})")
            sleep wait_time
            retry
          else
            # 最大リトライ回数を超えた場合
            Rails.logger.error('APIレート制限エラー: 最大リトライ回数に達しました')
            @error = 'Spotify APIのレート制限に達しました。しばらく時間をおいて再度お試しください。'
            break
          end
        rescue StandardError => e
          Rails.logger.error("プレイリスト取得エラー: #{e.message}")
          @error = "プレイリスト情報の取得中にエラーが発生しました: #{e.message}"
          break
        end

        @playlists.reverse!

        # 原曲名と一致するプレイリストのみ抽出するための処理
        original_song_titles = OriginalSong.distinct.pluck(:title)
        @playlists = @playlists.select { |p| p[:name].in?(original_song_titles) }

        # 取得成功後、Redisにキャッシュを保存
        redis.setex(cache_key, CACHE_TTL, @playlists.to_json) if @error.nil? && @playlists.present?
      rescue StandardError => e
        Rails.logger.error("予期せぬエラー: #{e.message}")
        @error = "プレイリスト情報の取得中に予期せぬエラーが発生しました: #{e.message}"
      end
    end

    def clear_cache
      redirect_to root_url unless session[:user_id]

      redis = RedisPool.get
      cache_key = "spotify_playlists:#{session[:user_id]}"
      redis.del(cache_key)

      redirect_to spotify_playlists_path
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
  end
end
