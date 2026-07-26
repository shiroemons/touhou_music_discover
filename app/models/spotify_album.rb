# frozen_string_literal: true

class SpotifyAlbum < ApplicationRecord
  default_scope { includes(:album).order('albums.jan_code desc') }

  has_many :spotify_tracks,
           -> { order(Arel.sql('spotify_tracks.disc_number ASC, spotify_tracks.track_number ASC')) },
           inverse_of: :spotify_album,
           dependent: :destroy

  belongs_to :album

  delegate :jan_code, :is_touhou, :circle_name, to: :album, allow_nil: true

  scope :is_touhou, -> { eager_load(:album).where(albums: { is_touhou: true }) }
  scope :non_touhou, -> { eager_load(:album).where(albums: { is_touhou: false }) }
  scope :spotify_id, ->(spotify_id) { find_by(spotify_id:) }
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }

  validates :album_id, uniqueness: { conditions: -> { active } }, if: :active?

  def self.save_album(s_album)
    # labelが "東方同人音楽流通" 以外は nil を返す
    return nil if s_album.label != ::Album::TOUHOU_MUSIC_LABEL

    album = ::Album.find_or_create_by!(jan_code: s_album.external_ids['upc'])
    existing_spotify_album = album.spotify_album
    return existing_spotify_album if existing_spotify_album.present? && existing_spotify_album.spotify_id != s_album.id

    spotify_album = ::SpotifyAlbum.find_or_initialize_by(spotify_id: s_album.id)
    spotify_album.assign_attributes(
      album:,
      album_type: s_album.album_type,
      name: s_album.name,
      label: s_album.label,
      url: s_album.external_urls['spotify'],
      total_tracks: s_album.total_tracks
    )
    spotify_album.save!

    if s_album.release_date
      release_date = begin
        Date.parse(s_album.release_date)
      rescue StandardError
        # release_date が "年のみ" の場合がある。 "01/01"を設定する
        Date.parse("#{s_album.release_date}/01/01")
      end
      spotify_album.update!(release_date:)
    end

    spotify_album.update!(payload: spotify_album.payload_preserving_available_markets(s_album.as_json))
    spotify_album
  end

  def artist_name
    # payload['artists']が1つ以上でその1つの名前がZUNの場合は、ZUNを削除して連結する
    return payload['artists'].reject { it['name'] == 'ZUN' }.map { it['name'] }.join(' / ') if payload['artists'].size > 1 && payload['artists'].any? { it['name'] == 'ZUN' }

    payload['artists']&.map { it['name'] }&.join(' / ')
  end

  def image_url
    return nil unless payload

    images = payload['images']
    return nil unless images&.first

    images.first['url'].presence
  end

  def available_markets
    Array(payload&.fetch('available_markets', nil))
  end

  def jp_available?
    available_markets.include?('JP')
  end

  def active_candidate_score
    [
      jp_available? ? 1 : 0,
      available_markets.any? ? 1 : 0,
      complete_tracks? ? 1 : 0,
      spotify_tracks.size,
      total_tracks.to_i,
      created_at.to_i,
      id
    ]
  end

  def self.preferred_active_album(spotify_albums)
    spotify_albums.max_by(&:active_candidate_score)
  end

  # Spotify は GET /albums/{id} から available_markets を段階的に削除しており、空で返ってきても
  # 配信が終了したことを意味しない。実測でも、非空から空に変わった4件すべてで market=JP を
  # 指定すると is_playable が true (restrictions は nil) だった。
  #
  # それを検証せずに payload を上書きすると、大多数のアルバムで jp_available? が true → false に
  # 反転する。jp_available? は active_candidate_score の最優先要素なので、preferred_active_album が
  # 重複アルバムの選択を誤り、正しい方のアルバムを非アクティブにしてしまう。これは Issue #559 の
  # 障害パターンそのものである。
  #
  # 逆に新しい値が非空なら、たとえ以前より件数が減っていてもそのまま採用する。配信国が実際に
  # 減ったのであれば、その減少は反映されるべきだから。
  #
  # これは恒久対応ではなく暫定措置である。本来の修正は Issue #559 で jp_available? と選択ロジックを
  # available_markets ではなく is_playable ベースに置き換えることであり、それが入ればこのガードは
  # 不要になる。
  def payload_preserving_available_markets(new_payload)
    fetched_payload = new_payload || {}
    existing_markets = Array(payload&.dig('available_markets'))
    return fetched_payload if existing_markets.blank? || Array(fetched_payload['available_markets']).present?

    Rails.logger.debug do
      "SpotifyAlbum##{id} (spotify_id: #{spotify_id}) の取得結果に available_markets が無いため、" \
        "既存の #{existing_markets.size} 件 (JP: #{existing_markets.include?('JP')}) を維持しました"
    end
    fetched_payload.merge('available_markets' => existing_markets)
  end

  private

  def complete_tracks?
    total_tracks.to_i.positive? && spotify_tracks.size >= total_tracks.to_i
  end
end
