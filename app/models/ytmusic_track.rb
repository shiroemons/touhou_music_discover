# frozen_string_literal: true

class YtmusicTrack < ApplicationRecord
  default_scope { includes(:album).order('albums.jan_code desc').order(track_number: :asc) }

  belongs_to :album
  belongs_to :ytmusic_album
  belongs_to :track

  delegate :jan_code, :is_touhou, :circle_name, to: :album, allow_nil: true
  delegate :isrc, to: :track, allow_nil: true
  delegate :image_url, to: :ytmusic_album, allow_nil: true

  scope :video_id, ->(video_id) { find_by(video_id:) }
  scope :album_browse_id, ->(browse_id) { eager_load(:ytmusic_album).where(ytmusic_album: { browse_id: }) }
  scope :is_touhou, -> { eager_load(:track).where(tracks: { is_touhou: true }) }
  scope :non_touhou, -> { eager_load(:track).where(tracks: { is_touhou: false }) }

  def self.fetch_tracks
    album_ids = Album.pluck(:id)
    batch_size = 1000
    album_ids.each_slice(batch_size) do |ids|
      Album.includes(:ytmusic_album, spotify_album: [:spotify_tracks], apple_music_album: [:apple_music_tracks]).where(id: ids).then do |records|
        Parallel.each(records, in_processes: 7) do |r|
          process_album(r)
        end
      end
    end
  end

  def self.process_album(album)
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

  def self.process_am_tracks(album, ytm_album, ytm_tracks)
    album.apple_music_album.apple_music_tracks.each do |am_track|
      ytm_track = ytm_tracks.find { it['track_number'] == am_track.track_number }
      next if ytm_track.nil?

      save_track(album.id, am_track.track_id, ytm_album, ytm_track)
    end
  end

  def self.process_sp_tracks(album, ytm_album, ytm_tracks)
    album.spotify_album.spotify_tracks.each do |s_track|
      ytm_track = ytm_tracks.find { it['track_number'] == s_track.track_number }
      next if ytm_track.nil?

      save_track(album.id, s_track.track_id, ytm_album, ytm_track)
    end
  end

  def self.save_track(album_id, track_id, ytm_album, ytm_track)
    ytmusic_track = ::YtmusicTrack.find_or_create_by!(
      album_id:,
      track_id:,
      ytmusic_album_id: ytm_album.id,
      video_id: ytm_track['video_id'],
      playlist_id: ytm_track['playlist_id'],
      name: ytm_track['title'],
      url: ytm_track['url'],
      track_number: ytm_track['track_number']
    )
    ytmusic_track.update(payload: ytm_track)
  end

  def update_track(ytm_track)
    update(
      name: ytm_track['title'],
      track_number: ytm_track['track_number'],
      payload: ytm_track
    )
  end

  def artist_name
    payload['artists']&.map { it['name'] }&.join(' / ')
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[album_id name payload playlist_id track_id track_number url video_id ytmusic_album_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[album track ytmusic_album]
  end
end
