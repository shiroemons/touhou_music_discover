# frozen_string_literal: true

class AppleMusicAlbum < ApplicationRecord
  has_many :apple_music_tracks,
           -> { order(Arel.sql('apple_music_tracks.track_number ASC')) },
           inverse_of: :apple_music_album,
           dependent: :destroy

  belongs_to :album, optional: true

  scope :missing_album, -> { where.missing(:album) }

  delegate :jan_code, to: :album, allow_nil: true

  # rubocop:disable Style/NumericLiterals
  VARIOUS_ARTISTS_ALBUMS_IDS = [
    1437759828, # 東方インストバッカー
    1437759890 # オールナイト・オブ・ナイツ
  ].freeze
  # rubocop:enable Style/NumericLiterals
end
