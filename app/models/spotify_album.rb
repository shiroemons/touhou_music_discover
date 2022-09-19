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

  def self.save_album(s_album)
    # labelが "東方同人音楽流通" 以外は nil を返す
    return nil if s_album.label != ::Album::TOUHOU_MUSIC_LABEL

    album = ::Album.find_or_create_by!(jan_code: s_album.external_ids['upc'])

    spotify_album = ::SpotifyAlbum.find_or_create_by!(
      album_id: album.id,
      spotify_id: s_album.id,
      album_type: s_album.album_type,
      name: s_album.name,
      label: s_album.label,
      url: s_album.external_urls['spotify'],
      total_tracks: s_album.total_tracks
    )

    if s_album.release_date
      release_date = begin
        Date.parse(s_album.release_date)
      rescue StandardError
        # release_date が "年のみ" の場合がある。 "01/01"を設定する
        Date.parse("#{s_album.release_date}/01/01")
      end
      spotify_album.update!(release_date:)
    end

    spotify_album.update!(payload: s_album.as_json)
    spotify_album
  end

  def artist_name
    payload['artists']&.map {_1['name']}&.join(' / ')
  end

  def image_url
    payload&.dig('images')&.first&.dig('url').presence
  end
end
