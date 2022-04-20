# frozen_string_literal: true

namespace :ytmusic do
  desc 'YouTubeMUSIC アルバムを検索してアルバム情報を取得'
  task search_albums_and_save: :environment do
    max_count = Album.missing_ytmusic_album.count
    count = 0
    Album.includes(:spotify_album, :apple_music_album).missing_ytmusic_album.order(:jan_code).each do |album|
      count += 1
      print "\rアルバム: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"

      next if album.jan_code == '4580547320978' # MICMNIS - Event Horizon

      sleep(0.2)
      s_album = album.spotify_album
      am_album = album.apple_music_album
      if s_album.present?
        browse_id = YtmusicAlbum::JAN_TO_ALBUM_BROWSE_IDS[album.jan_code]
        next if browse_id && YtmusicAlbum.find_and_save(browse_id, s_album)

        spotify_artist_names = s_album.payload['artists'].filter{ _1['name'] != 'ZUN' }&.map{_1['name']}&.join(' ')
        if s_album.name.unicode_normalize.include?('【睡眠用】東方ピアノ癒やし子守唄')
          s_album_name = s_album.name.unicode_normalize.sub(/\(.*\z/, '').tr('０-９', '0-9').strip
          query = "#{s_album_name} #{spotify_artist_names}"
          next if YtmusicAlbum.search_and_save(query, s_album)
        end
        s_album_name = s_album.name.unicode_normalize
                              .gsub(/( -|─|☆|■|≒|⇔)/, ' ')
                              .gsub(/\p{In_Halfwidth_and_Fullwidth_Forms}+/) { |str| str.unicode_normalize(:nfkd) }
                              .gsub(/ [(|（\[].*[)|）\]]/, '')
                              .tr('０-９', '0-9').strip
        query = "#{s_album_name} #{spotify_artist_names}"
        next if YtmusicAlbum.search_and_save(query, s_album)
        next if YtmusicAlbum.search_and_save(s_album_name, s_album)
        next if YtmusicAlbum.search_and_save(s_album_name.sub(/ [(|\[].*[)|\]]\z/, ''), s_album)
        next if YtmusicAlbum.search_and_save(s_album.name, s_album)
      end
      next if am_album.blank?

      am_album_name = am_album.name.gsub(/(-|─|☆|■|≒|⇔)/, '')
      artist_name = am_album.artist_name
      query = "#{am_album_name} #{artist_name}"
      next if YtmusicAlbum.search_and_save(query, am_album)
      next if YtmusicAlbum.search_and_save(am_album_name, am_album)
      next if YtmusicAlbum.search_and_save(am_album_name.sub(/ [(|\[].*[)|\]]\z/, ''), am_album)
      next if YtmusicAlbum.search_and_save(am_album.name, am_album)
      next if YtmusicAlbum.search_and_save(am_album.name.sub(' - EP', ''), am_album)
    end
  end

  desc 'YouTubeMUSIC アルバムの詳細情報を取得'
  task albums_update: :environment do
    max_count = YtmusicAlbum.count
    count = 0
    YtmusicAlbum.all.each do |ytmusic_album|
      count += 1
      print "\rアルバム: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"

      album = YTMusic::Album.find(ytmusic_album.browse_id)
      ytmusic_album.update_album(album) if album
    end
  end
end
