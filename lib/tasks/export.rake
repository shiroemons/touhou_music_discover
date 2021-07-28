# frozen_string_literal: true

namespace :export do
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
