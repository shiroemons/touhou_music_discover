# frozen_string_literal: true

namespace :touhou_music_discover do
  namespace :export do
    desc 'Touhou music with original songs file export'
    task touhou_music_with_original_songs: :environment do
      File.open('tmp/touhou_music_with_original_songs.tsv', 'w') do |f|
        f.puts("jan\tisrc\ttrack_number\tspotify_album_id\tspotify_track_id\tspotify_album_name\tspotify_track_name\tapple_music_album_id\tapple_music_track_id\tapple_music_album_name\tapple_music_track_name\toriginal_songs")
        SpotifyAlbum.includes(album: :apple_music_album, spotify_tracks: { track: :apple_music_track }).order(:release_date).each do |album|
          jan = album.jan_code
          spotify_album_id = album.spotify_id
          spotify_album_name = album.name
          apple_music_album_id = album.album&.apple_music_album&.apple_music_id
          apple_music_album_name = album.album&.apple_music_album&.name
          album.spotify_tracks.each do |track|
            isrc = track.isrc
            track_number = track.track_number
            spotify_track_id = track.spotify_id
            spotify_track_name = track.name
            apple_music_track_id = track.track&.apple_music_track&.apple_music_id
            apple_music_track_name = track.track&.apple_music_track&.name
            original_songs = track.track.original_songs.map { _1.title }.join('/')
            f.puts("#{jan}\t#{isrc}\t#{track_number}\t#{spotify_album_id}\t#{spotify_track_id}\t#{spotify_album_name}\t#{spotify_track_name}\t#{apple_music_album_id}\t#{apple_music_track_id}\t#{apple_music_album_name}\t#{apple_music_track_name}\t#{original_songs}")
          end
        end
        AppleMusicAlbum.missing_album.includes(album: :spotify_album, apple_music_tracks: { track: :spotify_track }).order(:release_date).each do |album|
          jan = album.jan_code
          apple_music_album_id = album.apple_music_id
          apple_music_album_name = album.name
          spotify_album_id = album.album&.spotify_album&.spotify_id
          spotify_album_name = album.album&.spotify_album&.name
          album.apple_music_tracks.each do |track|
            isrc = track.isrc
            track_number = track.track_number
            apple_music_track_id = track.apple_music_id
            apple_music_track_name = track.name
            spotify_track_id = track.track.spotify_track&.spotify_id
            spotify_track_name = track.track.spotify_track&.name
            original_songs = track.track.original_songs.map { _1.title }.join('/')
            f.puts("#{jan}\t#{isrc}\t#{track_number}\t#{spotify_album_id}\t#{spotify_track_id}\t#{spotify_album_name}\t#{spotify_track_name}\t#{apple_music_album_id}\t#{apple_music_track_id}\t#{apple_music_album_name}\t#{apple_music_track_name}\t#{original_songs}")
          end
        end
      end
    end

    desc 'Spotify touhou music file export'
    task spotify: :environment do
      File.open('tmp/spotify_touhou_music.tsv', 'w') do |f|
        f.puts("JAN\tISRC\tトラック番号\tアルバム名\t楽曲名\tアルバムURL\t楽曲URL")
        SpotifyAlbum.includes(:album, spotify_tracks: :track).order(:release_date).each do |album|
          jan = album.jan_code
          album_name = album.name
          album_url = album.url
          album.spotify_tracks.each do |track|
            isrc = track.isrc
            track_name = track.name
            track_number = track.track_number
            track_url = track.url
            f.puts("#{jan}\t#{isrc}\t#{track_number}\t#{album_name}\t#{track_name}\t#{album_url}\t#{track_url}")
          end
        end
      end
    end
  end

  namespace :import do
    desc 'Touhou music with original songs file import'
    task touhou_music_with_original_songs: :environment do
      require 'csv'
      songs = CSV.table('tmp/touhou_music_with_original_songs.tsv', col_sep: "\t", converters: nil, liberal_parsing: true)
      songs.each do |song|
        isrc = song[:isrc]
        original_songs = song[:original_songs]
        track = Track.find_by(isrc: isrc)
        if track && original_songs
          original_song_list = OriginalSong.where(title: original_songs.split('/'), is_duplicate: false)
          track.original_songs = original_song_list
        end
      end
    end
  end
end
