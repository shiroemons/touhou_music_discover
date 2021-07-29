# frozen_string_literal: true

namespace :apple_music do
  desc 'AppleMusic MasterArtistからアーティスト情報を取得'
  task master_artist_fetch: :environment do
    artists = MasterArtist.apple_music
    master_artist_count = 0
    max_master_artist_count = artists.count
    artists.each do |artist|
      AppleMusicClient::Artist.fetch(artist.key) unless AppleMusicArtist.exists?(apple_music_id: artist.key)
      master_artist_count += 1
      print "\rマスターアーティスト: #{master_artist_count}/#{max_master_artist_count} Progress: #{(master_artist_count * 100.0 / max_master_artist_count).round(1)}%"
    end
  end

  desc 'AppleMusic アーティストに紐づくアルバム情報を取得'
  task artists_album_fetch: :environment do
    apple_music_artists = AppleMusicArtist.all
    apple_music_artist_count = 0
    max_apple_music_artist_count = apple_music_artists.count
    print "\rAppleMusicアーティスト: #{apple_music_artist_count}/#{max_apple_music_artist_count} Progress: #{(apple_music_artist_count * 100.0 / max_apple_music_artist_count).round(1)}%"
    apple_music_artists.each do |apple_music_artist|
      AppleMusicClient::Album.fetch_artists_albums(apple_music_artist.apple_music_id)
      apple_music_artist_count += 1
      print "\rAppleMusicアーティスト: #{apple_music_artist_count}/#{max_apple_music_artist_count} Progress: #{(apple_music_artist_count * 100.0 / max_apple_music_artist_count).round(1)}%"
    end
  end

  desc 'AppleMusic アルバムに紐づくトラック情報を取得'
  task album_tracks_fetch: :environment do
    apple_music_albums = AppleMusicAlbum.all
    apple_music_album_count = 0
    max_apple_music_album_count = apple_music_albums.count
    print "\rAppleMusicアルバム: #{apple_music_album_count}/#{max_apple_music_album_count} Progress: #{(apple_music_album_count * 100.0 / max_apple_music_album_count).round(1)}%"
    apple_music_albums.each do |album|
      AppleMusicClient::Track.fetch_album_tracks(album)
      apple_music_album_count += 1
      print "\rAppleMusicアルバム: #{apple_music_album_count}/#{max_apple_music_album_count} Progress: #{(apple_music_album_count * 100.0 / max_apple_music_album_count).round(1)}%"
    end
  end

  desc 'AppleMusic ISRCからトラック情報を取得し、アルバム情報を取得'
  task isrc_fetch: :environment do
    missing_apple_music_tracks = Track.missing_apple_music_track
    count = 0
    max_count = missing_apple_music_tracks.count
    print "\rトラック: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"
    missing_apple_music_tracks.each do |track|
      tracks = AppleMusic::Song.get_collection_by_isrc(track.isrc)
      tracks.each do |t|
        t.albums.each do |album|
          apple_music_album = AppleMusicClient::Album.fetch(album.id)
          AppleMusicClient::Track.fetch_album_tracks(apple_music_album) if apple_music_album
        end
      end
      count += 1
      print "\rトラック: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"
    end
  end
end
