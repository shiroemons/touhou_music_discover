# frozen_string_literal: true

class FetchYtmusicTrack < Avo::BaseAction
  self.name = 'Fetch ytmusic track'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    album_ids = Album.pluck(:id)
    batch_size = 1000
    album_ids.each_slice(batch_size) do |ids|
      Album.includes(:ytmusic_album, spotify_album: [:spotify_tracks], apple_music_album: [:apple_music_tracks]).where(id: ids).then do |records|
        Parallel.each_with_index(records, in_processes: 7) do |r|
          process_album(r)
        end
      end
    end

    succeed 'Done!'
    reload
  end

  def process_album(album)
    ytm_album = album.ytmusic_album
    return if ytm_album.blank? || ytm_album.total_tracks == ytm_album.ytmusic_tracks.size

    ytm_tracks = ytm_album.payload&.dig('tracks')
    return if ytm_tracks.blank?

    if album.apple_music_album.present?
      process_am_tracks(album, ytm_album, ytm_tracks)
    elsif album.spotify_album.present?
      process_sp_tracks(album, ytm_album, ytm_tracks)
    end
  end

  def process_am_tracks(album, ytm_album, ytm_tracks)
    album.apple_music_album.apple_music_tracks.each do |am_track|
      ytm_track = ytm_tracks.find { _1['track_number'] == am_track.track_number }
      next if ytm_track.nil?

      YtmusicTrack.save_track(album.id, am_track.track_id, ytm_album, ytm_track)
    end
  end

  def process_sp_tracks(album, ytm_album, ytm_tracks)
    album.spotify_album.spotify_tracks.each do |s_track|
      ytm_track = ytm_tracks.find { _1['track_number'] == s_track.track_number }
      next if ytm_track.nil?

      YtmusicTrack.save_track(album.id, s_track.track_id, ytm_album, ytm_track)
    end
  end
end
