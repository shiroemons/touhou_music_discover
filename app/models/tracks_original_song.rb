# frozen_string_literal: true

class TracksOriginalSong < ApplicationRecord
  belongs_to :original_song, foreign_key: :original_song_code, inverse_of: :tracks_original_songs
  belongs_to :track
end
