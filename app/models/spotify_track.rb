# frozen_string_literal: true

class SpotifyTrack < ApplicationRecord
  belongs_to :spotify_album
  belongs_to :track

  delegate :isrc, to: :track, allow_nil: true
end
