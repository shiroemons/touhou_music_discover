# frozen_string_literal: true

module Spotify
  class PlaylistsController < ApplicationController
    LIMIT = 50

    def create
      redirect_to root_url unless session[:user_id]

      auth_hash = JSON.parse(Redis.current.get(session[:user_id]))
      @spotify_user = RSpotify::User.new(auth_hash)

      offset = 0
      @playlists = []
      loop do
        playlists = @spotify_user.playlists(limit: LIMIT, offset:)
        offset += LIMIT
        @playlists.push(*playlists)
        break if playlists.count < LIMIT
      end
      @playlists.reverse!
      # Original.includes(:original_songs).windows.each { |original| add_tracks(original) }
      # Original.includes(:original_songs).pc98.each { |original| add_tracks(original) }
      # Original.includes(:original_songs).zuns_music_collection.each { |original| add_tracks(original) }
      # Original.includes(:original_songs).akyus_untouched_score.each { |original| add_tracks(original) }
      # Original.includes(:original_songs).commercial_books.each { |original| add_tracks(original) }
    end

    private

    def add_tracks(original)
      original.original_songs.each do |os|
        next if os.is_duplicate

        spotify_tracks = os.spotify_tracks
        next if spotify_tracks.size.zero?

        original_song_title = os.title
        playlist = playlist_find(original_song_title)
        next if playlist.nil?

        playlist_tracks = playlist.tracks
        # 既存のプレイリストのtrackをすべて削除する
        until playlist_tracks.empty?
          playlist.remove_tracks!(playlist_tracks)
          playlist_tracks = playlist.tracks
        end
        spotify_track_ids = spotify_tracks.map(&:spotify_id)
        spotify_track_ids&.each_slice(50) do |ids|
          tracks = RSpotify::Track.find(ids)
          playlist.add_tracks!(tracks)
        end
      end
    end

    def playlist_find(playlist_name)
      @playlists.find { _1.name == playlist_name }
    end
  end
end
