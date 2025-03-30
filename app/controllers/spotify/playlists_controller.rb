# frozen_string_literal: true

module Spotify
  class PlaylistsController < ApplicationController
    LIMIT = 50

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
          begin
            process_playlist_update(@update_type, @spotify_user, session[:user_id])
          rescue => e
            Rails.logger.error("プレイリスト更新エラー: #{e.message}")
            redis = RedisPool.get
            update_info = JSON.parse(redis.get(progress_key))
            update_info['status'] = 'error'
            update_info['error_message'] = e.message
            redis.set(progress_key, update_info.to_json)
          ensure
            ActiveRecord::Base.connection_pool.release_connection
          end
        end
        
        # 進捗確認ページにリダイレクト
        redirect_to spotify_playlists_progress_path
      else
        # 通常のプレイリスト表示処理
        offset = 0
        @playlists = []
        loop do
          playlists = @spotify_user.playlists(limit: LIMIT, offset:)
          offset += LIMIT
          @playlists.push(*playlists)
          break if playlists.count < LIMIT
        end
        @playlists.reverse!
        
        # 原曲名と一致するプレイリストのみ抽出するための処理
        original_song_titles = OriginalSong.distinct.pluck(:title)
        @playlists = @playlists.select { |p| original_song_titles.include?(p.name) }
      end
    end
    
    def progress
      redis = RedisPool.get
      progress_key = "playlist_update:#{session[:user_id]}"
      
      @update_info = redis.get(progress_key).present? ? JSON.parse(redis.get(progress_key)) : {}
      @completed = @update_info['status'] == 'completed'
      
      # 更新が完了していればメッセージを表示
      if @completed
        case @update_info['update_type']
        when 'windows'
          @message = 'Windowsシリーズの原曲別プレイリストの更新が完了しました'
        when 'pc98'
          @message = 'PC-98シリーズの原曲別プレイリストの更新が完了しました'
        when 'zuns_music_collection'
          @message = "ZUN's Music Collectionの原曲別プレイリストの更新が完了しました"
        when 'akyus_untouched_score'
          @message = '幺樂団の歴史の原曲別プレイリストの更新が完了しました'
        when 'commercial_books'
          @message = '商業書籍の原曲別プレイリストの更新が完了しました'
        else
          @message = 'プレイリストの更新が完了しました'
        end
        
        # 処理時間を計算
        if @update_info['started_at'].present? && @update_info['completed_at'].present?
          started_at = Time.parse(@update_info['started_at'])
          completed_at = Time.parse(@update_info['completed_at'])
          @processing_time = (completed_at - started_at).to_i
        end
      end
    end

    private
    
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
        total_count += original.original_songs.reject(&:is_duplicate).count
      end
      
      # Redisに総数を保存
      update_info = JSON.parse(redis.get(progress_key))
      update_info['total'] = total_count
      redis.set(progress_key, update_info.to_json)
      
      current_count = 0
      
      originals.each do |original|
        # 原作ごとの曲数をカウント
        original_songs_count = original.original_songs.reject(&:is_duplicate).count
        current_original_name = original.title
        
        # 原作情報をRedisに更新
        update_info = JSON.parse(redis.get(progress_key))
        update_info['current_original'] = current_original_name
        update_info['songs_in_original'] = original_songs_count
        redis.set(progress_key, update_info.to_json)
        
        original.original_songs.each do |os|
          begin
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
          rescue => e
            Rails.logger.error("Error processing song #{os.title}: #{e.message}")
            next
          end
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
        end
      end
      
      @playlists.find { _1.name == playlist_name }
    end
  end
end
