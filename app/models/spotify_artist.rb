# frozen_string_literal: true

class SpotifyArtist < ApplicationRecord
  EXCLUDE_SPOTIFY_IDS = [
    '2XEx6N3gknSmtshM0PVuxu' # GUMI
  ].freeze
end
