# frozen_string_literal: true

class SpotifyTrack < ApplicationRecord
  belongs_to :album
  belongs_to :spotify_album
  belongs_to :track

  delegate :isrc, :is_touhou, to: :track, allow_nil: true

  scope :spotify_id, ->(spotify_id) { find_by(spotify_id: spotify_id) }
end
