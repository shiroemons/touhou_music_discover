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

  desc 'AppleMusic Various Artistsのアルバムとトラックを取得'
  task various_artists_albums_fetch: :environment do
    AppleMusicAlbum::VARIOUS_ARTISTS_ALBUMS_IDS.each do |album_id|
      apple_music_album = AppleMusicClient::Album.fetch(album_id)
      AppleMusicClient::Track.fetch_album_tracks(apple_music_album) if apple_music_album
    end
  end

  desc 'AppleMusic AppleMusicAlbumとAppleMusicTrackにalbum_idを設定する'
  task set_album_id: :environment do
    Album.includes(:spotify_album).missing_apple_music_album.each do |album|
      track_ids = album.tracks.pluck(:id)
      album_name = album.spotify_album.name
      release_date = album.spotify_album.release_date
      total_tracks = album.spotify_album.total_tracks
      apple_music_albums = AppleMusicAlbum.includes(:apple_music_tracks).where(apple_music_tracks: { track_id: track_ids }, release_date: release_date, total_tracks: total_tracks)
      apple_music_albums = AppleMusicAlbum.includes(:apple_music_tracks).where(apple_music_tracks: { track_id: track_ids }, total_tracks: total_tracks) if apple_music_albums.empty?
      count = apple_music_albums.size
      if count == 1
        apple_music_album = apple_music_albums.first
        apple_music_album.update!(album_id: album.id)
        apple_music_album.apple_music_tracks.update_all(album_id: album.id) # rubocop:disable Rails/SkipsModelValidations
      elsif count > 1
        apple_music_albums.each do |am_album|
          puts "#{count}件\tSpotify: #{album_name}\tAppleMusic: #{am_album.name}"
        end
      else
        albums = AppleMusicAlbum.where(name: album_name, total_tracks: total_tracks)
        count = albums.size
        if count == 1
          apple_music_album = albums.first
          apple_music_album.update!(album_id: album.id)
          apple_music_album.apple_music_tracks.update_all(album_id: album.id) # rubocop:disable Rails/SkipsModelValidations
        else
          puts "AppleMusicに #{album_name} は、存在しません"
        end
      end
    end
  end
end
