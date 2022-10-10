# frozen_string_literal: true

class FetchLineMusicTrack < Avo::BaseAction
  self.name = 'Fetch line music track'
  self.standalone = true
  self.visible = ->(resource:, view:) { view == :index }

  def handle(_args)
    Album.includes(:spotify_album, :apple_music_album, :line_music_album).find_each do |album|
      next if album.line_music_album.blank?

      lm_album = album.line_music_album
      next if lm_album.total_tracks == lm_album.line_music_tracks.size

      lm_tracks = LineMusic::Album.tracks(lm_album.line_music_id)
      if album.spotify_album.present?
        s_tracks = album.spotify_album.spotify_tracks
        lm_tracks.each do |lm_track|
          s_track = s_tracks.find { |t| t.disc_number == lm_track.disc_number && t.track_number == lm_track.track_number }
          LineMusicTrack.save_track(s_track.album_id, s_track.track_id, lm_album, lm_track) if s_track
        end
      elsif album.apple_music_album.present?
        am_tracks = album.apple_music_album.apple_music_tracks
        lm_tracks.each do |lm_track|
          am_track = am_tracks.find { |t| t.disc_number == lm_track.disc_number && t.track_number == lm_track.track_number }
          LineMusicTrack.save_track(am_track.album_id, am_track.track_id, lm_album, lm_track) if am_track
        end
      end
    end
  end
end
