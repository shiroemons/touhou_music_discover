# frozen_string_literal: true

namespace :spotify do
  desc 'Spotify label:東方同人音楽流通 のアルバムとトラックを年代ごとに取得'
  task fetch_touhou_albums: :environment do
    SpotifyClient::Album.fetch_touhou_albums
    puts "\n完了しました。"
  end

  desc 'Spotify Audio Featuresを取得'
  task fetch_audio_features: :environment do
    count = 0
    max_count = SpotifyTrack.count
    print "\rSpotify 楽曲: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"
    SpotifyTrack.eager_load(:album, :spotify_album, :track).find_in_batches(batch_size: 100) do |spotify_tracks|
      Retryable.retryable(tries: 5, sleep: 15, on: [RestClient::TooManyRequests, RestClient::InternalServerError]) do |retries, exception|
        puts "try #{retries} failed with exception: #{exception}" if retries.positive?

        SpotifyClient::AudioFeatures.fetch_by_spotify_tracks(spotify_tracks)
      end
      count += spotify_tracks.size
      print "\rSpotify 楽曲: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"
      sleep 0.5
    end
    puts "\n完了しました。"
  end

  desc 'Spotify SpotifyAlbumの情報を更新'
  task update_spotify_albums: :environment do
    count = 0
    max_count = SpotifyAlbum.count
    SpotifyAlbum.eager_load(:album).find_in_batches(batch_size: 20) do |spotify_albums|
      Retryable.retryable(tries: 5, sleep: 15, on: [RestClient::TooManyRequests, RestClient::InternalServerError]) do |retries, exception|
        puts "try #{retries} failed with exception: #{exception}" if retries.positive?

        SpotifyClient::Album.update_albums(spotify_albums)
      end
      count += spotify_albums.size
      print "\rSpotify アルバム: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"
      sleep 0.5
    end
  end

  desc 'Spotify SpotifyTrackの情報を更新'
  task update_spotify_tracks: :environment do
    count = 0
    max_count = SpotifyTrack.count
    SpotifyTrack.eager_load(:album, :spotify_album, :track).find_in_batches(batch_size: 50) do |spotify_tracks|
      Retryable.retryable(tries: 5, sleep: 15, on: [RestClient::TooManyRequests, RestClient::InternalServerError]) do |retries, exception|
        puts "try #{retries} failed with exception: #{exception}" if retries.positive?

        SpotifyClient::Track.update_tracks(spotify_tracks)
      end
      count += spotify_tracks.size
      print "\rSpotify 楽曲: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"
      sleep 0.5
    end
  end
end
