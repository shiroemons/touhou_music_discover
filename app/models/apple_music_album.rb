# frozen_string_literal: true

class AppleMusicAlbum < ApplicationRecord
  has_many :apple_music_tracks,
           -> { order(Arel.sql('apple_music_tracks.track_number ASC')) },
           inverse_of: :apple_music_album,
           dependent: :destroy

  belongs_to :album, optional: true

  delegate :jan_code, :is_touhou, to: :album, allow_nil: true

  scope :apple_music_id, ->(apple_music_id) { find_by(apple_music_id: apple_music_id) }
  scope :is_touhou, -> { eager_load(:album).where(albums: { is_touhou: true }) }
  scope :non_touhou, -> { eager_load(:album).where(albums: { is_touhou: false }) }
  scope :missing_album, -> { where.missing(:album) }

  # rubocop:disable Style/NumericLiterals
  VARIOUS_ARTISTS_ALBUMS_IDS = [
    1437759828, # 東方インストバッカー
    1437759890 # オールナイト・オブ・ナイツ
  ].freeze
  # rubocop:enable Style/NumericLiterals
end
