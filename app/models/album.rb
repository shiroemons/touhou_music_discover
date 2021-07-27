# frozen_string_literal: true

class Album < ApplicationRecord
  TOUHOU_MUSIC_LABEL = '東方同人音楽流通'

  has_many :albums_tracks, dependent: :destroy
  has_many :tracks, through: :albums_tracks
end
