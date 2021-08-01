# frozen_string_literal: true

class AppleMusicTrack < ApplicationRecord
  belongs_to :album
  belongs_to :apple_music_album
  belongs_to :track

  delegate :isrc, :is_touhou, to: :track, allow_nil: true

  scope :apple_music_id, ->(apple_music_id) { find_by(apple_music_id: apple_music_id) }
  scope :is_touhou, -> { eager_load(:track).where(tracks: { is_touhou: true }) }
  scope :non_touhou, -> { eager_load(:track).where(tracks: { is_touhou: false }) }
end
