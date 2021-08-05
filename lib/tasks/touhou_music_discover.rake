# frozen_string_literal: true

require 'csv'

namespace :touhou_music_discover do
  namespace :export do
    desc 'Touhou music with original songs file export'
    task touhou_music_with_original_songs: :environment do
      File.open('tmp/touhou_music_with_original_songs.tsv', 'w') do |f|
        f.puts("jan\tisrc\ttrack_number\tspotify_album_id\tspotify_track_id\tspotify_album_name\tspotify_track_name\tapple_music_album_id\tapple_music_track_id\tapple_music_album_name\tapple_music_track_name\toriginal_songs")
        Album.includes(:spotify_album, :apple_music_album, tracks: %i[spotify_track apple_music_track]).order(jan_code: :asc).each do |album|
          jan = album.jan_code
          apple_music_album_id = album.apple_music_album&.apple_music_id
          apple_music_album_name = album.apple_music_album&.name
          spotify_album_id = album.spotify_album&.spotify_id
          spotify_album_name = album.spotify_album&.name
          album.tracks.sort_by(&:isrc).each do |track|
            isrc = track.isrc
            track_number = track.apple_music_track&.track_number || track.spotify_track&.spotify_id
            apple_music_track_id = track.apple_music_track&.apple_music_id
            apple_music_track_name = track.apple_music_track&.name
            spotify_track_id = track.spotify_track&.spotify_id
            spotify_track_name = track.spotify_track&.name
            original_songs = track.original_songs.map(&:title).join('/')
            f.puts("#{jan}\t#{isrc}\t#{track_number}\t#{spotify_album_id}\t#{spotify_track_id}\t#{spotify_album_name}\t#{spotify_track_name}\t#{apple_music_album_id}\t#{apple_music_track_id}\t#{apple_music_album_name}\t#{apple_music_track_name}\t#{original_songs}")
          end
        end
      end
    end

    desc 'Touhou music file export'
    task touhou_music: :environment do
      File.open('tmp/touhou_music.tsv', 'w') do |f|
        f.puts("jan\tisrc\tno\tspotify_artist_name\tspotify_album_name\tspotify_track_name\tspotify_album_url\tspotify_track_url\tapple_music_artist_name\tapple_music_album_name\tapple_music_track_name\tapple_music_album_url\tapple_music_track_url")
        Album.order(jan_code: :asc).each do |album|
          jan = album.jan_code
          apple_music_album_url = album.apple_music_album&.url
          apple_music_album_name = album.apple_music_album&.name
          spotify_album_url = album.spotify_album&.url
          spotify_album_name = album.spotify_album&.name
          album.tracks.sort_by(&:isrc).each do |track|
            isrc = track.isrc
            apple_music_track = track.apple_music_tracks&.find { _1.album == album }
            spotify_track = track.spotify_tracks&.find { _1.album == album }
            track_number = apple_music_track&.track_number || spotify_track&.track_number
            apple_music_artist_name = apple_music_track&.artist_name
            apple_music_track_url = apple_music_track&.url
            apple_music_track_name = apple_music_track&.name

            spotify_artist_name = spotify_track&.artist_name
            spotify_track_url = spotify_track&.url
            spotify_track_name = spotify_track&.name
            f.puts("#{jan}\t#{isrc}\t#{track_number}\t#{spotify_artist_name}\t#{spotify_album_name}\t#{spotify_track_name}\t#{spotify_album_url}\t#{spotify_track_url}\t#{apple_music_artist_name}\t#{apple_music_album_name}\t#{apple_music_track_name}\t#{apple_music_album_url}\t#{apple_music_track_url}")
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

    desc 'Output Spotify albums and songs as JSON for Algolia'
    task spotify_albums_tracks_for_algolia: :environment do
      File.open('tmp/touhou_music_spotify_for_algolia.json', 'w') do |file|
        albums = Album.eager_load(spotify_tracks: { track: { original_songs: :original } })
        file.puts(JSON.pretty_generate(AlbumsToAlgoliaPresenter.new(albums).as_json))
      end
    end
  end

  namespace :import do
    desc 'Touhou music with original songs file import'
    task touhou_music_with_original_songs: :environment do
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

    desc 'GitHub fetch Touhou music with original songs file import'
    task fetch_touhou_music_with_original_songs: :environment do
      url = 'https://raw.githubusercontent.com/shiroemons/touhou_streaming_with_original_songs/main/touhou_music_with_original_songs.tsv'
      token = ENV['GITHUB_TOKEN']
      if token.present?
        headers = { 'Authorization' => "token #{token}" }
        response = Faraday.get(url, nil, headers)
        songs = CSV.new(response.body, col_sep: "\t", converters: nil, liberal_parsing: true, encoding: 'UTF-8', headers: true)
        songs = songs.read
        songs.inspect

        max_songs = songs.size
        songs.each.with_index(1) do |song, song_count|
          isrc = song['isrc']
          original_songs = song['original_songs']
          track = Track.find_by(isrc: isrc)
          if track && original_songs
            original_song_list = OriginalSong.where(title: original_songs.split('/'), is_duplicate: false)
            track.original_songs = original_song_list
          end
          print "\r東方楽曲: #{song_count}/#{max_songs} Progress: #{(song_count * 100.0 / max_songs).round(1)}%"
        end
      else
        puts 'GITHUB_TOKEN を設定してください。'
      end
    end
  end

  desc '原曲情報を見て is_touhouフラグを変更する'
  task change_is_touhou_flag: :environment do
    # Trackのis_touhouフラグを変更
    Track.includes(:original_songs).each do |track|
      original_songs = track.original_songs
      is_touhou = original_songs.all? { _1.title != 'オリジナル' } && !original_songs.all? { _1.title == 'その他' }
      track.update(is_touhou: is_touhou) if track.is_touhou != is_touhou
    end

    # Albumのis_touhouフラグを変更
    Album.includes(:tracks).each do |album|
      is_touhou = !album.tracks.all? { _1.is_touhou == false }
      album.update!(is_touhou: is_touhou) if album.is_touhou != is_touhou
    end
  end
end
