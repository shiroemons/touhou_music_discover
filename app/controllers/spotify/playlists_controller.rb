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
      @updated = false
      @message = nil

      # プレイリスト更新の処理
      if @update_type.present?
        case @update_type
        when 'windows'
          Original.includes(:original_songs).windows.each { |original| add_tracks(original) }
          @message = 'Windowsシリーズの原曲別プレイリストの更新が完了しました'
        when 'pc98'
          Original.includes(:original_songs).pc98.each { |original| add_tracks(original) }
          @message = 'PC-98シリーズの原曲別プレイリストの更新が完了しました'
        when 'zuns_music_collection'
          Original.includes(:original_songs).zuns_music_collection.each { |original| add_tracks(original) }
          @message = "ZUN's Music Collectionの原曲別プレイリストの更新が完了しました"
        when 'akyus_untouched_score'
          Original.includes(:original_songs).akyus_untouched_score.each { |original| add_tracks(original) }
          @message = '幺樂団の歴史の原曲別プレイリストの更新が完了しました'
        when 'commercial_books'
          Original.includes(:original_songs).commercial_books.each { |original| add_tracks(original) }
          @message = '商業書籍の原曲別プレイリストの更新が完了しました'
        else
          @message = '無効な更新タイプが指定されました'
        end
        @updated = true
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

    private

    def add_tracks(original)
      original.original_songs.each do |os|
        count = 0
        begin
          next if os.is_duplicate

          spotify_tracks = os.spotify_tracks
          next if spotify_tracks.empty?

          original_song_title = os.title
          playlist = playlist_find(original_song_title)
          if playlist.nil?
            new_playlist = @spotify_user.create_playlist!(original_song_title)
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
        rescue OpenSSL::SSL::SSLError => e
          Rails.logger.warn(e)
          count += 1
          next unless count < 3

          sleep 1
          retry
        end
      end
    end

    def playlist_find(playlist_name)
      @playlists ||= []

      offset = 0
      if @playlists.empty?
        loop do
          playlists = @spotify_user.playlists(limit: LIMIT, offset:)
          offset += LIMIT
          @playlists.push(*playlists)
          break if playlists.count < LIMIT
        end
      end

      @playlists.find { _1.name == playlist_name }
    end
  end
end
