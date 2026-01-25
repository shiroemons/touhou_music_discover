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
  scope :stale, -> { where(synced_at: nil).or(where(synced_at: ...24.hours.ago)) }

  def self.ransackable_attributes(_auth_object = nil)
    %w[name original_song_code spotify_id spotify_user_id synced_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[original_song]
  end
end
