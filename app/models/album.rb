# frozen_string_literal: true

class Album < ApplicationRecord
  TOUHOU_MUSIC_LABEL = '東方同人音楽流通'

  has_many :albums_tracks, dependent: :destroy
  has_many :tracks, through: :albums_tracks

  has_one :apple_music_album, dependent: :destroy
  has_one :spotify_album, dependent: :destroy

  scope :missing_apple_music_album, -> { where.missing(:apple_music_album) }
  scope :missing_spotify_album, -> { where.missing(:spotify_album) }
end
