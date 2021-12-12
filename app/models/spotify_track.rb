# frozen_string_literal: true

class SpotifyTrack < ApplicationRecord
  has_one :spotify_track_audio_feature, dependent: :destroy

  belongs_to :album
  belongs_to :spotify_album
  belongs_to :track

  delegate :isrc, :is_touhou, to: :track, allow_nil: true

  scope :is_touhou, -> { eager_load(:track).where(tracks: { is_touhou: true }) }
  scope :non_touhou, -> { eager_load(:track).where(tracks: { is_touhou: false }) }
  scope :spotify_id, ->(spotify_id) { find_by(spotify_id: spotify_id) }
  scope :album_spotify_id, ->(spotify_id) { eager_load(:spotify_album).where(spotify_album: { spotify_id: spotify_id }) }
  scope :bpm, ->(bpm) { eager_load(:spotify_track_audio_feature).where(spotify_track_audio_feature: { tempo: bpm }) }

  def self.save_track(spotify_album, s_track)
    return nil if spotify_album.blank? || s_track.blank?

    track = ::Track.find_or_create_by!(jan_code: spotify_album.album.jan_code, isrc: s_track.external_ids['isrc'])
    spotify_album.album.tracks << track unless spotify_album.album.tracks.include?(track)

    spotify_track = ::SpotifyTrack.find_or_create_by!(
      album_id: spotify_album.album.id,
      track_id: track.id,
      spotify_album_id: spotify_album.id,
      spotify_id: s_track.id,
      name: s_track.name,
      label: spotify_album.label,
      url: s_track.external_urls['spotify'],
      release_date: spotify_album.release_date,
      disc_number: s_track.disc_number,
      track_number: s_track.track_number,
      duration_ms: s_track.duration_ms
    )
    spotify_track.update!(payload: s_track.as_json)
    spotify_track
  end

  def artist_name
    payload['artists']&.map{_1['name']}&.join(' / ')
  end
end
