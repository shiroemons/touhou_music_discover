# frozen_string_literal: true

class YtmusicTrack < ApplicationRecord
  default_scope { includes(:album).order('albums.jan_code desc').order(track_number: :asc) }

  belongs_to :album
  belongs_to :ytmusic_album
  belongs_to :track

  delegate :jan_code, :is_touhou, :circle_name, to: :album, allow_nil: true
  delegate :isrc, :is_touhou, to: :track, allow_nil: true
  delegate :image_url, to: :ytmusic_album, allow_nil: true

  scope :video_id, ->(video_id) { find_by(video_id:) }
  scope :album_browse_id, ->(browse_id) { eager_load(:ytmusic_album).where(ytmusic_album: { browse_id: }) }
  scope :is_touhou, -> { eager_load(:track).where(tracks: { is_touhou: true }) }
  scope :non_touhou, -> { eager_load(:track).where(tracks: { is_touhou: false }) }

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
    payload['artists']&.map { _1['name'] }&.join(' / ')
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[album_id name payload playlist_id track_id track_number url video_id ytmusic_album_id]
  end
end
