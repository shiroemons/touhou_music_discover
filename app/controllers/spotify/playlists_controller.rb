# frozen_string_literal: true

module Spotify
  class PlaylistsController < ApplicationController
    LIMIT = 50
    MAX_RETRIES = 3

    def index
      redirect_to root_url unless session[:user_id]

      redis = RedisPool.get
      auth_hash = JSON.parse(redis.get(session[:user_id]))
      @spotify_user = RSpotify::User.new(auth_hash)

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
      rescue StandardError => e
        Rails.logger.error("予期せぬエラー: #{e.message}")
        @error = "プレイリスト情報の取得中に予期せぬエラーが発生しました: #{e.message}"
      end
    end

    def create
      redirect_to root_url unless session[:user_id]

      redis = RedisPool.get
      auth_hash = JSON.parse(redis.get(session[:user_id]))
      @spotify_user = RSpotify::User.new(auth_hash)

      @update_type = params[:update_type]

      if @update_type.present?
        # 進捗状況をRedisに保存するためのキー
        progress_key = "playlist_update:#{session[:user_id]}"

        # 更新処理開始前にRedisを初期化
        update_info = {
          update_type: @update_type,
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

        # 非同期処理を開始
        Thread.new do
          process_playlist_update(@update_type, @spotify_user, session[:user_id])
        rescue StandardError => e
          Rails.logger.error("プレイリスト更新エラー: #{e.message}")
          redis = RedisPool.get
          update_info = JSON.parse(redis.get(progress_key))
          update_info['status'] = 'error'
          update_info['error_message'] = e.message
          redis.set(progress_key, update_info.to_json)
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
      redis = RedisPool.get
      progress_key = "playlist_update:#{session[:user_id]}"

      @update_info = redis.get(progress_key).present? ? JSON.parse(redis.get(progress_key)) : {}
      @completed = @update_info['status'] == 'completed'

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

    private

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

    def process_playlist_update(update_type, spotify_user, user_id)
      redis = RedisPool.get
      progress_key = "playlist_update:#{user_id}"

      originals = case update_type
                  when 'windows'
                    Original.includes(:original_songs).windows
                  when 'pc98'
                    Original.includes(:original_songs).pc98
                  when 'zuns_music_collection'
                    Original.includes(:original_songs).zuns_music_collection
                  when 'akyus_untouched_score'
                    Original.includes(:original_songs).akyus_untouched_score
                  when 'commercial_books'
                    Original.includes(:original_songs).commercial_books
                  else
                    []
                  end

      # 総処理数をカウント
      total_count = 0
      originals.each do |original|
        total_count += original.original_songs.count { |element| !element.is_duplicate }
      end

      # Redisに総数を保存
      update_info = JSON.parse(redis.get(progress_key))
      update_info['total'] = total_count
      redis.set(progress_key, update_info.to_json)

      current_count = 0

      originals.each do |original|
        # 原作ごとの曲数をカウント
        original_songs_count = original.original_songs.count { |element| !element.is_duplicate }
        current_original_name = original.title

        # 原作情報をRedisに更新
        update_info = JSON.parse(redis.get(progress_key))
        update_info['current_original'] = current_original_name
        update_info['songs_in_original'] = original_songs_count
        redis.set(progress_key, update_info.to_json)

        original.original_songs.each do |os|
          next if os.is_duplicate

          spotify_tracks = os.spotify_tracks
          next if spotify_tracks.empty?

          # 現在処理中の曲名とアレンジ曲数をRedisに更新
          update_info = JSON.parse(redis.get(progress_key))
          update_info['current_song'] = os.title
          update_info['current'] = current_count
          update_info['arrangement_count'] = spotify_tracks.size
          redis.set(progress_key, update_info.to_json)

          original_song_title = os.title
          playlist = playlist_find(original_song_title, spotify_user)
          if playlist.nil?
            new_playlist = spotify_user.create_playlist!(original_song_title)
            playlist = RSpotify::Playlist.find_by_id(new_playlist.id)
          end

          playlist_tracks = playlist.tracks
          # 既存のプレイリストのtrackをすべて削除する
          until playlist_tracks.empty?
            playlist.remove_tracks!(playlist_tracks)
            playlist_tracks = playlist.tracks
          end
          spotify_track_ids = spotify_tracks.map(&:spotify_id)
          spotify_track_ids&.each_slice(50) do |ids|
            tracks = RSpotify::Track.find(ids)
            playlist.add_tracks!(tracks) if tracks.length.positive?
          end

          current_count += 1
        rescue OpenSSL::SSL::SSLError => e
          Rails.logger.warn(e)
          retry_count = 0
          retry_count += 1
          next unless retry_count < 3

          sleep 1
          retry
        rescue RestClient::TooManyRequests => e
          # 429エラーの詳細情報をログに出力
          Rails.logger.error("APIレート制限エラー詳細: ステータスコード=#{e.http_code}, ヘッダー=#{e.http_headers.inspect}")
          Rails.logger.error("レスポンス本文: #{e.http_body}") if e.respond_to?(:http_body)

          # Retry-Afterヘッダーの確認
          retry_after = e.respond_to?(:http_headers) && e.http_headers[:retry_after].to_i
          if retry_after && retry_after > 60
            Rails.logger.error("APIレート制限の待機時間が長すぎます: #{retry_after}秒")

            # 進捗情報の更新
            formatted_time = format_seconds(retry_after)
            update_info = JSON.parse(redis.get(progress_key))
            update_info['status'] = 'error'
            update_info['error_message'] = "APIレート制限に達しました。サーバーが #{formatted_time} の待機を要求しています。"
            redis.set(progress_key, update_info.to_json)
            return
          end

          retry_count = retry_count.to_i + 1
          if retry_count <= MAX_RETRIES
            wait_time = 2**retry_count # エクスポネンシャルバックオフ
            Rails.logger.warn("APIレート制限到達: #{wait_time}秒待機してリトライします (#{retry_count}/#{MAX_RETRIES})")
            sleep wait_time
            retry
          else
            Rails.logger.error('APIレート制限エラー: 最大リトライ回数に達しました')
            next
          end
        rescue StandardError => e
          Rails.logger.error("Error processing song #{os.title}: #{e.message}")
          next
        end
      end

      # 更新完了を記録
      update_info = JSON.parse(redis.get(progress_key))
      update_info['status'] = 'completed'
      update_info['completed_at'] = Time.current.to_s
      update_info['current'] = total_count
      redis.set(progress_key, update_info.to_json)
    end

    def playlist_find(playlist_name, spotify_user = nil)
      @playlists ||= []
      spotify_user ||= @spotify_user

      offset = 0
      if @playlists.empty?
        loop do
          playlists = spotify_user.playlists(limit: LIMIT, offset:)
          offset += LIMIT
          @playlists.push(*playlists)
          break if playlists.count < LIMIT

          # API制限に引っかからないよう、リクエスト間に少し待機
          sleep 1
        rescue RestClient::TooManyRequests => e
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

          retry_count = retry_count.to_i + 1
          if retry_count <= MAX_RETRIES
            wait_time = 2**retry_count # エクスポネンシャルバックオフ
            Rails.logger.warn("APIレート制限到達: #{wait_time}秒待機してリトライします (#{retry_count}/#{MAX_RETRIES})")
            sleep wait_time
            retry
          else
            Rails.logger.error('APIレート制限エラー: 最大リトライ回数に達しました')
            break
          end
        end
      end

      # ハッシュの場合とオブジェクトの場合の両方に対応
      @playlists.find do |p|
        if p.is_a?(Hash) || p.is_a?(ActiveSupport::HashWithIndifferentAccess)
          p[:name] == playlist_name
        else
          p.name == playlist_name
        end
      end
    end
  end
end
