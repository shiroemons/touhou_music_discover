# frozen_string_literal: true

class FetchLineMusicTrack < Avo::BaseAction
  self.name = 'Fetch line music track'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    album_ids = Album.pluck(:id)
    batch_size = 1000
    album_ids.each_slice(batch_size) do |ids|
      Album.includes(:spotify_album, :apple_music_album, :line_music_album).where(id: ids).then do |records|
        Parallel.each(records, in_processes: 7) do |r|
          process_album(r)
        end
      end
    end

    succeed 'Done!'
    reload
  end

  def process_album(album)
    return if album.line_music_album.blank?

    lm_album = album.line_music_album
    return if lm_album.total_tracks == lm_album.line_music_tracks.size

    if album.spotify_album.present?
      match_and_save_tracks_for_spotify(album.spotify_album, lm_album)
    elsif album.apple_music_album.present?
      match_and_save_tracks_for_apple_music(album.apple_music_album, lm_album)
    end
  end

  def match_and_save_tracks_for_spotify(spotify_album, line_music_album)
    lm_tracks = LineMusic::Album.tracks(line_music_album.line_music_id)
    spotify_album.spotify_tracks.each do |s_track|
      lm_track = lm_tracks.find { |lm| lm.disc_number == s_track.disc_number && lm.track_number == s_track.track_number }
      LineMusicTrack.save_track(s_track.album_id, s_track.track_id, line_music_album, lm_track) if lm_track
    end
  end

  def match_and_save_tracks_for_apple_music(apple_music_album, line_music_album)
    lm_tracks = LineMusic::Album.tracks(line_music_album.line_music_id)
    apple_music_album.apple_music_tracks.each do |am_track|
      lm_track = lm_tracks.find { |lm| lm.disc_number == am_track.disc_number && lm.track_number == am_track.track_number }
      LineMusicTrack.save_track(am_track.album_id, am_track.track_id, line_music_album, lm_track) if lm_track
    end
  end
end
