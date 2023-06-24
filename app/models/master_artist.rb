# frozen_string_literal: true

class MasterArtist < ApplicationRecord
  enum streaming_type: { apple_music: 'apple_music', spotify: 'spotify' }

  def self.ransackable_attributes(_auth_object = nil)
    %w[id key name streaming_type]
  end
end
