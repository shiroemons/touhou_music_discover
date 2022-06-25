# frozen_string_literal: true

namespace :ytmusic do
  desc 'YouTube Music アルバムを検索してアルバム情報を取得'
  task search_albums_and_save: :environment do
    max_count = Album.missing_ytmusic_album.count
    count = 0
    Album.includes(:spotify_album, :apple_music_album).missing_ytmusic_album.order(:jan_code).each do |album|
      count += 1
      print "\rアルバム: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"

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

  desc 'YouTube Music アルバム情報からトラック情報を取得'
  task album_tracks_save: :environment do
    max_count = Album.count
    count = 0
    Album.includes(:ytmusic_album, spotify_album: [:spotify_tracks], apple_music_album: [:apple_music_tracks]).each do |album|
      count += 1
      print "\rアルバム: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"

      ytm_album = album.ytmusic_album
      next if ytm_album.blank?

      next if ytm_album.total_tracks == ytm_album.ytmusic_tracks.size

      ytm_tracks = ytm_album.payload&.dig('tracks')

      s_album = album.spotify_album
      if s_album.present?
        s_album.spotify_tracks.each do |s_track|
          ytm_track = ytm_tracks.find { _1['track_number'] == s_track.track_number }
          next if ytm_track.nil?

          YtmusicTrack.save_track(album.id, s_track.track_id, ytm_album, ytm_track)
        end
        next
      end

      am_album = album.apple_music_album
      next if am_album.blank?

      am_album.apple_music_tracks.each do |am_track|
        ytm_track = ytm_tracks.find { _1['track_number'] == am_track.track_number }
        next if ytm_track.nil?

        YtmusicTrack.save_track(album.id, am_track.track_id, ytm_album, ytm_track)
      end
    end
  end

  desc 'YouTube Music アルバム情報を取得'
  task fetch_albums: :environment do
    max_count = YtmusicAlbum.where(url: nil).count
    count = 0
    YtmusicAlbum.where(url: nil).each do |ytmusic_album|
      count += 1
      print "\rアルバム: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"

      album = YTMusic::Album.find(ytmusic_album.browse_id)
      url = "https://music.youtube.com/browse/#{ytmusic_album.browse_id}"
      ytmusic_album.update_album(album, url) if album
    end
  end

  desc 'YouTube Music アルバムとトラック情報を更新'
  task update_album_and_tracks: :environment do
    max_count = YtmusicAlbum.count
    count = 0
    YtmusicAlbum.all.each do |ytmusic_album|
      count += 1
      print "\rアルバム: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"

      album = YTMusic::Album.find(ytmusic_album.browse_id)
      url = "https://music.youtube.com/browse/#{ytmusic_album.browse_id}"
      ytmusic_album.update_album(album, url) if album

      tracks = ytmusic_album.payload['tracks']
      ytmusic_album.ytmusic_tracks.each do |ytm_track|
        track = tracks.find { _1['track_number'] == ytm_track.track_number }
        ytm_track.update_track(track) if track
      end
    end
  end
end
