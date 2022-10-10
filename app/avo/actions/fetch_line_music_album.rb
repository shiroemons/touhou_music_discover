# frozen_string_literal: true

class FetchLineMusicAlbum < Avo::BaseAction
  self.name = 'Fetch line music album'
  self.standalone = true
  self.visible = ->(resource:, view:) { view == :index }

  def handle(_args)
    Album.includes(:spotify_album, :apple_music_album).missing_line_music_album.find_each do |album|
      s_album = album.spotify_album
      am_album = album.apple_music_album
      if s_album.present?
        spotify_artist_names = s_album.payload['artists'].map { _1['name'] }.sort
        query = "#{s_album.name} #{spotify_artist_names}"
        next if LineMusicAlbum.search_and_save(query, s_album)
        next if LineMusicAlbum.search_and_save(s_album.name, s_album)
        next if LineMusicAlbum.search_and_save(s_album.name.tr('〜~', '～'), s_album)
        next if LineMusicAlbum.search_and_save(s_album.name.unicode_normalize, s_album)
        next if LineMusicAlbum.search_and_save(s_album.name.sub(/ [(|\[].*[)|\]]\z/, ''), s_album)

        line_album_id = LineMusicAlbum::JAN_TO_ALBUM_IDS[album.jan_code]
        next if line_album_id && LineMusicAlbum.find_and_save(line_album_id, s_album)
      end
      next if am_album.blank?

      artist_name = am_album.payload.dig('attributes', 'artist_name')
      query = "#{am_album.name.sub(' - EP', '')} #{artist_name}"
      next if LineMusicAlbum.search_and_save(query, am_album)
      next if LineMusicAlbum.search_and_save(am_album.name, am_album)
      next if LineMusicAlbum.search_and_save(am_album.name.sub(/ [(|\[].*[)|\]]\z/, ''), am_album)
    end

    LineMusicAlbum.where(url: nil).find_each do |line_music_album|
      lm_album = LineMusic::Album.find(line_music_album.line_music_id)
      if lm_album.present?
        line_music_album.update(
          name: lm_album.album_title,
          url: "https://music.line.me/webapp/album/#{line_music_album.line_music_id}",
          total_tracks: lm_album.track_total_count,
          release_date: lm_album.release_date,
          payload: lm_album.as_json
        )
      end
    end
  end
end
