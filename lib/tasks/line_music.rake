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
        spotify_artist_names = s_album.payload['artists'].map { it['name'] }.sort
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

  desc 'LINE MUSIC アルバムのトラック情報を取得'
  task album_tracks_find_and_save: :environment do
    max_count = Album.count
    count = 0
    Album.includes(:spotify_album, :apple_music_album, :line_music_album).each do |album|
      count += 1
      print "\rアルバム: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"
      next if album.line_music_album.blank?

      lm_album = album.line_music_album

      next if lm_album.total_tracks == lm_album.line_music_tracks.size

      lm_tracks = LineMusic::Album.tracks(lm_album.line_music_id)

      if album.spotify_album.present?
        s_tracks = album.spotify_album.spotify_tracks
        lm_tracks.each do |lm_track|
          s_track = s_tracks.find { |t| t.disc_number == lm_track.disc_number && t.track_number == lm_track.track_number }
          LineMusicTrack.save_track(s_track.album_id, s_track.track_id, lm_album, lm_track) if s_track
        end
      elsif album.apple_music_album.present?
        am_tracks = album.apple_music_album.apple_music_tracks
        lm_tracks.each do |lm_track|
          am_track = am_tracks.find { |t| t.disc_number == lm_track.disc_number && t.track_number == lm_track.track_number }
          LineMusicTrack.save_track(am_track.album_id, am_track.track_id, lm_album, lm_track) if am_track
        end
      end
    end
    puts "\n完了しました。"
  end

  desc 'LINE MUSIC LineMusicAlbumの情報を取得'
  task fetch_albums: :environment do
    count = 0
    max_count = LineMusicAlbum.where(url: nil).count
    LineMusicAlbum.where(url: nil).all.each do |line_music_album|
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
      count += 1
      print "\rLINE MUSIC アルバム: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"
    end
  end

  desc 'LINE MUSIC LineMusicAlbumの情報を更新'
  task update_line_music_albums: :environment do
    count = 0
    max_count = LineMusicAlbum.count
    LineMusicAlbum.all.each do |line_music_album|
      lm_album = LineMusic::Album.find(line_music_album.line_music_id)
      if lm_album.present?
        line_music_album.update(
          name: lm_album.album_title,
          total_tracks: lm_album.track_total_count,
          payload: lm_album.as_json
        )
      end
      count += 1
      print "\rLINE MUSIC アルバム: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"
    end
  end

  desc 'LINE MUSIC LineMusicTrackの情報を更新'
  task update_line_music_tracks: :environment do
    count = 0
    max_count = LineMusicTrack.count
    LineMusicAlbum.eager_load(:line_music_tracks).each do |line_music_album|
      lm_tracks = LineMusic::Album.tracks(line_music_album.line_music_id)
      line_music_album.line_music_tracks.each do |line_music_track|
        lm_track = lm_tracks.find { it.track_id == line_music_track.line_music_id }
        next if lm_track.blank?

        line_music_track.update(
          name: lm_track.track_title,
          disc_number: lm_track.disc_number,
          track_number: lm_track.track_number,
          payload: lm_track.as_json
        )
      end
      count += line_music_album.total_tracks
      print "\rLINE MUSIC 楽曲: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"
    end
  end
end
