# frozen_string_literal: true

class SpotifyTrack < ApplicationRecord
  has_one :spotify_track_audio_feature, dependent: :destroy

  belongs_to :album
  belongs_to :spotify_album
  belongs_to :track

  delegate :isrc, :is_touhou, to: :track, allow_nil: true

  scope :spotify_id, ->(spotify_id) { find_by(spotify_id: spotify_id) }
  scope :bpm, ->(bpm) { eager_load(:spotify_track_audio_feature).where(spotify_track_audio_feature: { tempo: bpm }) }
end
