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
    1437759890, # オールナイト・オブ・ナイツ
    1582445297, # 東方ダンジョンダイブ (Original Sound Track)
    1583684648, # 東方オトハナビ
    1583694708 # 東方オトハナビ
  ].freeze
  # rubocop:enable Style/NumericLiterals

  # AppleMusicのアルバム情報を保存する
  def self.save_album(am_album)
    return nil if am_album.record_label != ::Album::TOUHOU_MUSIC_LABEL

    apple_music_album = ::AppleMusicAlbum.find_or_create_by!(
      apple_music_id: am_album.id,
      name: am_album.name,
      label: am_album.record_label,
      url: am_album.url,
      release_date: am_album.release_date,
      total_tracks: am_album.track_count
    )

    jan_code = am_album.upc
    album = ::Album.find_or_create_by!(jan_code: jan_code)

    apple_music_album.update(
      album_id: album.id,
      payload: am_album.as_json
    )
    apple_music_album
  end

  def artist_name
    payload.dig('attributes', 'artist_name')
  end
end
