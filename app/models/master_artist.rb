# frozen_string_literal: true

class MasterArtist < ApplicationRecord
  enum streaming_type: { apple_music: 'apple_music', spotify: 'spotify' }
end
