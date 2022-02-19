# frozen_string_literal: true

class AppleMusicTrack < ApplicationRecord
  belongs_to :album, optional: true
  belongs_to :apple_music_album
  belongs_to :track

  delegate :isrc, :is_touhou, to: :track, allow_nil: true

  scope :apple_music_id, ->(apple_music_id) { find_by(apple_music_id:) }
  scope :is_touhou, -> { eager_load(:track).where(tracks: { is_touhou: true }) }
  scope :non_touhou, -> { eager_load(:track).where(tracks: { is_touhou: false }) }

  def self.save_track(apple_music_album, am_track)
    track = ::Track.find_or_create_by!(jan_code: apple_music_album.album.jan_code, isrc: am_track.isrc)

    apple_music_track = ::AppleMusicTrack.find_or_create_by!(
      track_id: track.id,
      apple_music_album_id: apple_music_album.id,
      apple_music_id: am_track.id,
      name: am_track.name,
      label: apple_music_album.label,
      artist_name: am_track.artist_name,
      composer_name: am_track.composer_name.to_s,
      url: am_track.url,
      release_date: am_track.release_date,
      disc_number: am_track.disc_number,
      track_number: am_track.track_number,
      duration_ms: am_track.duration_in_millis
    )
    apple_music_track.update!(
      album_id: apple_music_album.album_id,
      payload: am_track.as_json
    )
    apple_music_track
  end
end
