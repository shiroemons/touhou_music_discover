# frozen_string_literal: true

class Track < ApplicationRecord
  has_many :albums_tracks, dependent: :destroy
  has_many :albums, through: :albums_tracks
end
