# frozen_string_literal: true

class SpotifyTrackAudioFeature < ApplicationRecord
  belongs_to :track
  belongs_to :spotify_track
end
