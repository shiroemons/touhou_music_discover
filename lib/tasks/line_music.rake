# frozen_string_literal: true

namespace :line_music do
  desc 'LINE MUSIC アルバムを検索して情報を取得'
  task search_albums_and_save: :environment do
    max_count = Album.missing_line_music_album.count
    count = 0
    Album.includes(:spotify_album, :apple_music_album).missing_line_music_album.each do |album|
      count += 1
      print "\rアルバム: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"

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
    puts "\n完了しました。"
  end
end
