# frozen_string_literal: true

class AppleMusicTrack < ApplicationRecord
  belongs_to :album
  belongs_to :apple_music_album
  belongs_to :track

  delegate :isrc, :is_touhou, to: :track, allow_nil: true
end
