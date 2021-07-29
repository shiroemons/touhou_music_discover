# frozen_string_literal: true

class AppleMusicTrack < ApplicationRecord
  belongs_to :apple_music_album
  belongs_to :track

  delegate :isrc, to: :track, allow_nil: true
end
