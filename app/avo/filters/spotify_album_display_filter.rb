# frozen_string_literal: true

class SpotifyAlbumDisplayFilter < Avo::Filters::SelectFilter
  self.name = 'Spotify album display'

  def apply(_request, query, value)
    duplicate_album_ids = SpotifyAlbum.unscoped
                                      .select(:album_id)
                                      .group(:album_id)
                                      .having('COUNT(*) > 1')

    case value
    when 'duplicated_active'
      query.where(album_id: duplicate_album_ids)
    when 'duplicated_all'
      SpotifyAlbum.unscoped.where(album_id: duplicate_album_ids)
    when 'inactive'
      SpotifyAlbum.unscoped.inactive
    when 'all'
      SpotifyAlbum.unscoped
    else
      query.active
    end
  end

  def options
    {
      active: 'アクティブのみ',
      duplicated_active: '重複あり（アクティブ）',
      duplicated_all: '重複あり（全履歴）',
      inactive: '非アクティブ',
      all: 'すべて'
    }
  end
end
