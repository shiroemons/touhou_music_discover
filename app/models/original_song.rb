# frozen_string_literal: true

class OriginalSong < ApplicationRecord
  self.primary_key = :code

  has_many :tracks_original_songs, foreign_key: :original_song_code, inverse_of: :original_song, dependent: :destroy
  has_many :tracks, through: :tracks_original_songs
  has_many :apple_music_tracks, through: :tracks
  has_many :spotify_tracks, through: :tracks

  belongs_to :original,
             foreign_key: :original_code,
             primary_key: :code,
             inverse_of: :original_songs

  delegate :title, :short_title, :original_type, :series_order, to: :original, allow_nil: true, prefix: true

  scope :non_duplicated, -> { where(is_duplicate: false) }

  def self.ransackable_attributes(_auth_object = nil)
    %w[code composer is_duplicate original_code title track_number]
  end
end
