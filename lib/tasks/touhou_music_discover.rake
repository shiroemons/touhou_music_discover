# frozen_string_literal: true

require 'csv'

namespace :touhou_music_discover do
  namespace :export do
    desc 'Touhou music with original songs file export'
    task touhou_music_with_original_songs: :environment do
      File.open('tmp/touhou_music_with_original_songs.tsv', 'w') do |f|
        f.puts("jan\tisrc\ttrack_number\tspotify_album_id\tspotify_track_id\tspotify_album_name\tspotify_track_name\tapple_music_album_id\tapple_music_track_id\tapple_music_album_name\tapple_music_track_name\toriginal_songs")
        Album.includes(:spotify_album, :apple_music_album, tracks: %i[spotify_tracks apple_music_tracks]).order(jan_code: :asc).each do |album|
          jan = album.jan_code
          # 特定のアルバムのみ出力する場合、コメントをオフにする
          # next if jan != ''

          apple_music_album = album.apple_music_album
          apple_music_album_id = apple_music_album&.apple_music_id
          apple_music_album_name = apple_music_album&.name
          spotify_album = album.spotify_album
          spotify_album_id = spotify_album&.spotify_id
          spotify_album_name = spotify_album&.name
          album.tracks.sort_by(&:isrc).each do |track|
            isrc = track.isrc
            apple_music_track = track.apple_music_track(album)
            spotify_track = track.spotify_track(album)
            track_number = apple_music_track&.track_number || spotify_track&.track_number
            apple_music_track_id = apple_music_track&.apple_music_id
            apple_music_track_name = apple_music_track&.name
            spotify_track_id = spotify_track&.spotify_id
            spotify_track_name = spotify_track&.name
            original_songs = track.original_songs.map(&:title).join('/')

            # 原曲の紐付けがまだの楽曲を出力する場合、コメントをオフにする
            # next if original_songs.present?

            f.puts("#{jan}\t#{isrc}\t#{track_number}\t#{spotify_album_id}\t#{spotify_track_id}\t#{spotify_album_name}\t#{spotify_track_name}\t#{apple_music_album_id}\t#{apple_music_track_id}\t#{apple_music_album_name}\t#{apple_music_track_name}\t#{original_songs}")
          end
        end
      end
    end

    desc 'Touhou music file export'
    task touhou_music: :environment do
      File.open('tmp/touhou_music.tsv', 'w') do |f|
        f.puts("jan\tisrc\tno\tcircle\tspotify_album_artist_name\tspotify_album_name\tspotify_track_name\tspotify_album_url\tspotify_track_url\tapple_music_album_artist_name\tapple_music_album_name\tapple_music_track_name\tapple_music_album_url\tapple_music_track_url\tyoutube_music_album_artist_name\tyoutube_music_album_name\tyoutube_music_track_name\tyoutube_music_album_url\tyoutube_music_track_url\tline_music_album_artist_name\tline_music_album_name\tline_music_track_name\tline_music_album_url\tline_music_track_url")
        Album.includes(:circles, :apple_music_album, :line_music_album, :spotify_album, :ytmusic_album, tracks: %i[apple_music_tracks line_music_tracks spotify_tracks ytmusic_tracks]).order(jan_code: :asc).each do |album|
          jan = album.jan_code
          circle = album.circles&.map { _1.name }&.join(' / ')

          # Spotify
          spotify_album_url = album.spotify_album&.url
          spotify_album_artist_name = album.spotify_album&.artist_name
          spotify_album_name = album.spotify_album&.name
          # Apple Music
          apple_music_album_url = album.apple_music_album&.url
          apple_music_album_artist_name = album.apple_music_album&.artist_name
          apple_music_album_name = album.apple_music_album&.name
          # YouTube Music
          youtube_music_album_url = album.ytmusic_album&.url
          youtube_music_album_artist_name = album.ytmusic_album&.artist_name
          youtube_music_album_name = album.ytmusic_album&.name
          # LINE MUSIC
          line_music_album_url = album.line_music_album&.url
          line_music_album_artist_name = album.line_music_album&.artist_name
          line_music_album_name = album.line_music_album&.name

          # track_numberでソート
          tracks = album.tracks.sort_by do |track|
            track.apple_music_tracks&.find { _1.album == album }&.track_number || track.spotify_tracks&.find { _1.album == album }&.track_number
          end

          tracks.each do |track|
            isrc = track.isrc
            apple_music_track = track.apple_music_tracks&.find { _1.album == album }
            line_music_track = track.line_music_tracks&.find { _1.album == album }
            spotify_track = track.spotify_tracks&.find { _1.album == album }
            ytmusic_track = track.ytmusic_tracks&.find { _1.album == album }

            track_number = apple_music_track&.track_number || spotify_track&.track_number

            # Spotify
            spotify_track_url = spotify_track&.url
            spotify_track_name = spotify_track&.name
            # Apple Music
            apple_music_track_url = apple_music_track&.url
            apple_music_track_name = apple_music_track&.name
            # YouTube Music
            youtube_music_track_url = ytmusic_track&.url
            youtube_music_track_name = ytmusic_track&.name
            # LINE MUSIC
            line_music_track_url = line_music_track&.url
            line_music_track_name = line_music_track&.name
            f.puts("#{jan}\t#{isrc}\t#{track_number}\t#{circle}\t#{spotify_album_artist_name}\t#{spotify_album_name}\t#{spotify_track_name}\t#{spotify_album_url}\t#{spotify_track_url}\t#{apple_music_album_artist_name}\t#{apple_music_album_name}\t#{apple_music_track_name}\t#{apple_music_album_url}\t#{apple_music_track_url}\t#{youtube_music_album_artist_name}\t#{youtube_music_album_name}\t#{youtube_music_track_name}\t#{youtube_music_album_url}\t#{youtube_music_track_url}\t#{line_music_album_artist_name}\t#{line_music_album_name}\t#{line_music_track_name}\t#{line_music_album_url}\t#{line_music_track_url}")
          end
        end
      end
    end

    desc 'Touhou music album only file export'
    task touhou_music_album_only: :environment do
      File.open('tmp/touhou_music_album_only.tsv', 'w') do |f|
        f.puts("jan\tcircle\tspotify_album_name\tspotify_album_url\tapple_music_album_name\tapple_music_album_url\tytmusic_album_name\tytmusic_album_url\tline_music_album_name\tline_music_album_url")
        Album.includes(:circles, :apple_music_album, :spotify_album, :line_music_album, :ytmusic_album).order(jan_code: :asc).each do |album|
          jan = album.jan_code
          circle = album.circles&.map { _1.name }&.join(' / ')
          spotify_album_name = album.spotify_album&.name
          spotify_album_url = album.spotify_album&.url
          apple_music_album_name = album.apple_music_album&.name
          apple_music_album_url = album.apple_music_album&.url
          ytmusic_album_name = album.ytmusic_album&.name
          ytmusic_album_url = album.ytmusic_album&.url
          line_music_album_name = album.line_music_album&.name
          line_music_album_url = album.line_music_album&.url

          f.puts("#{jan}\t#{circle}\t#{spotify_album_name}\t#{spotify_album_url}\t#{apple_music_album_name}\t#{apple_music_album_url}\t#{ytmusic_album_name}\t#{ytmusic_album_url}\t#{line_music_album_name}\t#{line_music_album_url}")
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

    desc 'Output albums and songs as JSON for Algolia'
    task for_algolia: :environment do
      File.open('tmp/touhou_music_spotify_for_algolia.json', 'w') do |file|
        albums = Album.eager_load(spotify_tracks: { track: { original_songs: :original } })
        file.puts(JSON.pretty_generate(SpotifyAlbumsToAlgoliaPresenter.new(albums).as_json))
      end

      File.open('tmp/touhou_music_apple_music_for_algolia.json', 'w') do |file|
        albums = Album.eager_load(apple_music_tracks: { track: { original_songs: :original } })
        file.puts(JSON.pretty_generate(AppleMusicAlbumsToAlgoliaPresenter.new(albums).as_json))
      end

      File.open('tmp/touhou_music_youtube_music_for_algolia.json', 'w') do |file|
        albums = Album.eager_load(ytmusic_tracks: { track: { original_songs: :original } })
        file.puts(JSON.pretty_generate(YtmusicAlbumsToAlgoliaPresenter.new(albums).as_json))
      end

      File.open('tmp/touhou_music_line_music_for_algolia.json', 'w') do |file|
        albums = Album.eager_load(line_music_tracks: { track: { original_songs: :original } })
        file.puts(JSON.pretty_generate(LineMusicAlbumsToAlgoliaPresenter.new(albums).as_json))
      end
    end

    desc 'Output files for random_touhou_music'
    task to_random_touhou_music: :environment do
      apple_music_songs = []
      AppleMusicAlbum.includes(apple_music_tracks: :track).is_touhou.order(release_date: :asc, id: :asc).each do |album|
        album.apple_music_tracks.sort_by(&:track_number).each do |track|
          next unless track.is_touhou

          track_name = track.name
          collection_name = album.name
          url = track.url
          apple_music_songs.push({ title: track_name, collection_name:, url: })
        end
      end

      File.open('tmp/apple_music_songs.json', 'w') do |f|
        f.puts JSON.pretty_generate(apple_music_songs)
      end

      apple_music_tsa_songs = []
      albums = AppleMusicAlbum.includes(album: :circles, apple_music_tracks: :track).is_touhou.order(release_date: :asc, id: :asc).where(circles: { name: '上海アリス幻樂団' })
      albums.each do |album|
        album.apple_music_tracks.sort_by(&:track_number).each do |track|
          next unless track.is_touhou

          track_name = track.name
          collection_name = album.name
          url = track.url
          apple_music_tsa_songs.push({ title: track_name, collection_name:, url: })
        end
      end

      File.open('tmp/apple_music_tsa_songs.json', 'w') do |f|
        f.puts JSON.pretty_generate(apple_music_tsa_songs)
      end

      ytmusic_songs = []
      YtmusicAlbum.includes(ytmusic_tracks: :track).is_touhou.order(release_year: :asc, id: :asc).each do |album|
        album.ytmusic_tracks.sort_by(&:track_number).each do |track|
          next unless track.is_touhou

          track_name = track.name
          collection_name = album.name
          url = track.url
          ytmusic_songs.push({ title: track_name, collection_name:, url: })
        end
      end

      File.open('tmp/youtube_music_songs.json', 'w') do |f|
        f.puts JSON.pretty_generate(ytmusic_songs)
      end

      ytmusic_tsa_songs = []
      albums = YtmusicAlbum.includes(album: :circles, ytmusic_tracks: :track).is_touhou.order(release_year: :asc, id: :asc).where(circles: { name: '上海アリス幻樂団' })
      albums.each do |album|
        album.ytmusic_tracks.sort_by(&:track_number).each do |track|
          next unless track.is_touhou

          track_name = track.name
          collection_name = album.name
          url = track.url
          ytmusic_tsa_songs.push({ title: track_name, collection_name:, url: })
        end
      end

      File.open('tmp/youtube_music_tsa_songs.json', 'w') do |f|
        f.puts JSON.pretty_generate(ytmusic_tsa_songs)
      end

      line_music_songs = []
      LineMusicAlbum.includes(line_music_tracks: :track).is_touhou.order(release_date: :asc, id: :asc).each do |album|
        album.line_music_tracks.sort_by(&:track_number).each do |track|
          next unless track.is_touhou

          track_name = track.name
          collection_name = album.name
          url = track.url
          line_music_songs.push({ title: track_name, collection_name:, url: })
        end
      end

      File.open('tmp/line_music_songs.json', 'w') do |f|
        f.puts JSON.pretty_generate(line_music_songs)
      end

      line_music_tsa_songs = []
      albums = LineMusicAlbum.includes(album: :circles, line_music_tracks: :track).is_touhou.order(release_date: :asc, id: :asc).where(circles: { name: '上海アリス幻樂団' })
      albums.each do |album|
        album.line_music_tracks.sort_by(&:track_number).each do |track|
          next unless track.is_touhou

          track_name = track.name
          collection_name = album.name
          url = track.url
          line_music_tsa_songs.push({ title: track_name, collection_name:, url: })
        end
      end

      File.open('tmp/line_music_tsa_songs.json', 'w') do |f|
        f.puts JSON.pretty_generate(line_music_tsa_songs)
      end

      spotify_songs = []
      SpotifyAlbum.includes(spotify_tracks: :track).is_touhou.order(release_date: :asc, id: :asc).each do |album|
        album.spotify_tracks.sort_by(&:track_number).each do |track|
          next unless track.is_touhou

          track_name = track.name
          collection_name = album.name
          url = track.url
          spotify_songs.push({ title: track_name, collection_name:, url: })
        end
      end

      File.open('tmp/spotify_songs.jso', 'w') do |f|
        f.puts JSON.pretty_generate(spotify_songs)
      end

      spotify_tsa_songs = []
      albums = SpotifyAlbum.includes(album: :circles, spotify_tracks: :track).is_touhou.order(release_date: :asc, id: :asc).where(circles: { name: '上海アリス幻樂団' })
      albums.each do |album|
        album.spotify_tracks.sort_by(&:track_number).each do |track|
          next unless track.is_touhou

          track_name = track.name
          collection_name = album.name
          url = track.url
          spotify_tsa_songs.push({ title: track_name, collection_name:, url: })
        end
      end

      File.open('tmp/spotify_tsa_songs.json', 'w') do |f|
        f.puts JSON.pretty_generate(spotify_tsa_songs)
      end
    end
  end

  namespace :import do
    desc 'Touhou music with original songs file import'
    task touhou_music_with_original_songs: :environment do
      songs = CSV.table('tmp/touhou_music_with_original_songs.tsv', col_sep: "\t", converters: nil, liberal_parsing: true)
      songs.each do |song|
        jan = song[:jan]
        isrc = song[:isrc]
        original_songs = song[:original_songs]
        track = Track.find_by(jan_code: jan, isrc:)
        if track && original_songs
          original_song_list = OriginalSong.where(title: original_songs.split('/'), is_duplicate: false)
          track.original_songs = original_song_list
        end
      end
    end

    desc 'GitHub fetch Touhou music with original songs file import'
    task fetch_touhou_music_with_original_songs: :environment do
      url = 'https://raw.githubusercontent.com/shiroemons/touhou_streaming_with_original_songs/main/touhou_music_with_original_songs.tsv'
      token = ENV.fetch('GITHUB_TOKEN', nil)
      if token.present?
        headers = { 'Authorization' => "token #{token}" }
        response = Faraday.get(url, nil, headers)
        songs = CSV.new(response.body, col_sep: "\t", converters: nil, liberal_parsing: true, encoding: 'UTF-8', headers: true)
        songs = songs.read
        songs.inspect

        max_songs = songs.size
        songs.each.with_index(1) do |song, song_count|
          jan = song['jan']
          isrc = song['isrc']
          original_songs = song['original_songs']
          track = Track.find_by(jan_code: jan, isrc:)
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
      track.update(is_touhou:) if track.is_touhou != is_touhou
    end

    # Albumのis_touhouフラグを変更
    Album.includes(:tracks).each do |album|
      # トラック内にis_touhouがtrueがあれば、そのアルバムはis_touhouはtrueとする
      is_touhou = album.tracks.map(&:is_touhou).any?
      album.update!(is_touhou:) if album.is_touhou != is_touhou
    end
  end

  desc 'アルバムにサークルを紐付ける'
  task associate_album_with_circle: :environment do
    Album.missing_circles.eager_load(:spotify_album).each do |album|
      artist_name = album&.spotify_album&.artist_name
      artist_name = artist_name&.sub(%r{\AZUN / }, '')
      artists = artist_name&.split(' / ')
      artists = artists&.map { Circle::SPOTIFY_ARTIST_TO_CIRCLE[_1].presence || _1 }&.flatten
      artists&.uniq&.each do |artist|
        circle = Circle.find_by(name: artist)
        album.circles.push(circle) if circle.present?
      end
      next unless album.circles.size.zero?

      artist = Circle::JAN_TO_CIRCLE[album.jan_code]
      circle = Circle.find_by(name: artist)
      album.circles.push(circle) if circle.present?
    end
  end
end
