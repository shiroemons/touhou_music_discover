# frozen_string_literal: true

class SpotifyPlaylist < ApplicationRecord
  belongs_to :original_song,
             primary_key: :code,
             foreign_key: :original_song_code,
             inverse_of: false,
             optional: true

  validates :spotify_id, presence: true, uniqueness: true
  validates :spotify_user_id, presence: true
  validates :name, presence: true

  scope :for_user, ->(user_id) { where(spotify_user_id: user_id) }
end
