# frozen_string_literal: true

namespace :apple_music do
  desc 'AppleMusic MasterArtistからAppleMusicのアーティスト情報を取得'
  task fetch_apple_music_artist_from_master_artists: :environment do
    max_count = MasterArtist.apple_music.count
    count = 0
    MasterArtist.apple_music.find_in_batches(batch_size: 25) do |master_artists|
      AppleMusicClient::Artist.fetch(master_artists.map(&:key))

      count += master_artists.size
      print "\rマスターアーティスト: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"
    end
    puts "\n完了しました。"
  end

  desc 'AppleMusic アーティストに紐づくアルバム情報を取得'
  task fetch_artist_albums: :environment do
    am_artist_ids = AppleMusicArtist.pluck(:apple_music_id)
    count = 0
    max_count = am_artist_ids.count
    am_artist_ids.each do |am_artist_id|
      AppleMusicClient::Album.fetch_artists_albums(am_artist_id)
      count += 1
      print "\rAppleMusicアーティスト: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"
    end
  end

  desc 'AppleMusic アルバムに紐づくトラック情報を取得'
  task fetch_album_tracks: :environment do
    apple_music_albums = AppleMusicAlbum.all
    count = 0
    max_count = apple_music_albums.count
    apple_music_albums.each do |apple_music_album|
      AppleMusicClient::Track.fetch_album_tracks(apple_music_album)
      count += 1
      print "\rAppleMusicアルバム: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"
    end
  end

  desc 'AppleMusic ISRCからトラック情報を取得し、アルバム情報を取得'
  task fetch_tracks_by_isrc: :environment do
    missing_apple_music_tracks = Track.missing_apple_music_tracks
    count = 0
    max_count = missing_apple_music_tracks.count
    missing_apple_music_tracks.each do |track|
      AppleMusicClient::Track.fetch_tracks_by_isrc(track.isrc)
      count += 1
      print "\rトラック: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"
    end
  end

  desc 'AppleMusic Various Artistsのアルバムとトラックを取得'
  task fetch_various_artists_albums: :environment do
    AppleMusicAlbum::VARIOUS_ARTISTS_ALBUMS_IDS.each do |album_id|
      apple_music_album = AppleMusicClient::Album.fetch(album_id)
      AppleMusicClient::Track.fetch_album_tracks(apple_music_album) if apple_music_album
    end
  end

  desc 'AppleMusic AppleMusicAlbumの情報を更新'
  task update_apple_music_albums: :environment do
    count = 0
    max_count = AppleMusicAlbum.count
    AppleMusicAlbum.eager_load(:album).find_in_batches(batch_size: 20) do |apple_music_albums|
      AppleMusicClient::Album.update_albums(apple_music_albums)
      count += apple_music_albums.size
      print "\rAppleMusic アルバム: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"
      sleep 0.5
    end
  end

  desc 'AppleMusic AppleMusicTrackの情報を更新'
  task update_apple_music_tracks: :environment do
    count = 0
    max_count = AppleMusicTrack.count
    AppleMusicTrack.eager_load(:album, :apple_music_album, :track).find_in_batches(batch_size: 50) do |apple_music_tracks|
      AppleMusicClient::Track.update_tracks(apple_music_tracks)

      count += apple_music_tracks.size
      print "\rAppleMusic 楽曲: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"
      sleep 0.5
    end
  end
end
