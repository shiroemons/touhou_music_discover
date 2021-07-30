# frozen_string_literal: true

class Track < ApplicationRecord
  has_many :tracks_original_songs, dependent: :destroy
  has_many :original_songs, through: :tracks_original_songs

  has_many :albums_tracks, dependent: :destroy
  has_many :albums, through: :albums_tracks

  has_one :apple_music_track, dependent: :destroy
  has_one :spotify_track, dependent: :destroy

  scope :missing_apple_music_track, -> { where.missing(:apple_music_track) }
  scope :missing_spotify_track, -> { where.missing(:spotify_track) }
  scope :missing_original_songs, -> { where.missing(:original_songs) }
  scope :is_touhou, -> { where(is_touhou: true) }
  scope :non_touhou, -> { where(is_touhou: false) }
  scope :jan, ->(jan) { joins(:albums).where(albums: { jan_code: jan }) }
  scope :isrc, ->(isrc) { find_by(isrc: isrc) }
end
