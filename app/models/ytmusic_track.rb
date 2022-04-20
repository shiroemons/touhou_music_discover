# frozen_string_literal: true

class YtmusicTrack < ApplicationRecord
  belongs_to :album
  belongs_to :ytmusic_album
  belongs_to :track

  delegate :isrc, :is_touhou, to: :track, allow_nil: true

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
end
