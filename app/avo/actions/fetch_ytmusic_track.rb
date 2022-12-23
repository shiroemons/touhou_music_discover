# frozen_string_literal: true

class FetchYtmusicTrack < Avo::BaseAction
  self.name = 'Fetch ytmusic track'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    Album.includes(:ytmusic_album, spotify_album: [:spotify_tracks], apple_music_album: [:apple_music_tracks]).find_each do |album|
      ytm_album = album.ytmusic_album
      next if ytm_album.blank?

      next if ytm_album.total_tracks == ytm_album.ytmusic_tracks.size

      ytm_tracks = ytm_album.payload&.dig('tracks')
      s_album = album.spotify_album
      if s_album.present?
        s_album.spotify_tracks.each do |s_track|
          ytm_track = ytm_tracks.find { _1['track_number'] == s_track.track_number }
          next if ytm_track.nil?

          YtmusicTrack.save_track(album.id, s_track.track_id, ytm_album, ytm_track)
        end
        next
      end

      am_album = album.apple_music_album
      next if am_album.blank?

      am_album.apple_music_tracks.each do |am_track|
        ytm_track = ytm_tracks.find { _1['track_number'] == am_track.track_number }
        next if ytm_track.nil?

        YtmusicTrack.save_track(album.id, am_track.track_id, ytm_album, ytm_track)
      end
    end

    succeed 'Done!'
    reload
  end
end
