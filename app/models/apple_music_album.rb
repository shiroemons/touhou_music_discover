# frozen_string_literal: true

class AppleMusicAlbum < ApplicationRecord
  has_many :apple_music_tracks,
           -> { order(Arel.sql('apple_music_tracks.track_number ASC')) },
           inverse_of: :apple_music_album,
           dependent: :destroy

  belongs_to :album, optional: true

  delegate :jan_code, to: :album, allow_nil: true
end
