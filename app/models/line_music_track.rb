# frozen_string_literal: true

class LineMusicTrack < ApplicationRecord
  belongs_to :album
  belongs_to :line_music_album
  belongs_to :track

  delegate :isrc, :is_touhou, to: :track, allow_nil: true

  scope :line_music_id, ->(line_music_id) { find_by(line_music_id:) }
  scope :album_line_music_id, ->(line_music_id) { eager_load(:line_music_album).where(line_music_album: { line_music_id: }) }
  scope :is_touhou, -> { eager_load(:track).where(tracks: { is_touhou: true }) }
  scope :non_touhou, -> { eager_load(:track).where(tracks: { is_touhou: false }) }

  def self.save_track(album_id, track_id, lm_album, lm_track)
    url = "https://music.line.me/webapp/track/#{lm_track.track_id}"

    line_music_track = ::LineMusicTrack.find_or_create_by!(
      album_id:,
      track_id:,
      line_music_album_id: lm_album.id,
      line_music_id: lm_track.track_id,
      name: lm_track.track_title,
      url:,
      disc_number: lm_track.disc_number,
      track_number: lm_track.track_number
    )
    line_music_track.update(payload: lm_track.as_json)
  end

  def artist_name
    payload['artists']&.map{_1['artist_name']}&.join(' / ')
  end
end
