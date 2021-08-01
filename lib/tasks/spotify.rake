# frozen_string_literal: true

namespace :spotify do
  desc 'Spotify MasterArtistからSpotifyのアーティスト情報を取得'
  task fetch_spotify_artist_from_master_artists: :environment do
    max_count = MasterArtist.spotify.count
    count = 0
    MasterArtist.spotify.find_in_batches(batch_size: 50) do |master_artists|
      Retryable.retryable(tries: 5, sleep: 15, on: [RestClient::TooManyRequests, RestClient::InternalServerError]) do |retries, exception|
        puts "try #{retries} failed with exception: #{exception}" if retries.positive?

        SpotifyClient::Artist.fetch(master_artists.map(&:key))
      end

      count += master_artists.size
      print "\rマスターアーティスト: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"
    end
    puts "\n完了しました。"
  end

  desc 'Spotify SpotifyTrackからアーティスト情報を取得'
  task fetch_spotify_track_artist: :environment do
    s_artist_ids = []
    SpotifyTrack.all.each.with_index(1) do |spotify_track, i|
      ids = spotify_track.payload['artists']&.map { _1['id'] }
      s_artist_ids.push(*ids)
      print "\r曲数 #{i}曲"
    end
    s_artist_ids.uniq!.compact!

    spotify_artist_ids = SpotifyArtist.pluck(:spotify_id)

    new_artist_ids = s_artist_ids - spotify_artist_ids
    new_artist_ids.each_slice(50) do |ids|
      Retryable.retryable(tries: 5, sleep: 15, on: [RestClient::TooManyRequests, RestClient::InternalServerError]) do |retries, exception|
        puts "try #{retries} failed with exception: #{exception}" if retries.positive?

        SpotifyClient::Artist.fetch(ids)
      end
    end
    puts "\n完了しました。"
  end

  desc 'Spotify アーティストに紐づくアルバム情報とトラック情報を取得'
  task fetch_albums_and_tracks: :environment do
    spotify_artist_ids = SpotifyArtist.pluck(:spotify_id)
    spotify_artist_ids.each_slice(50) do |ids|
      SpotifyClient::Album.fetch(ids)
    end
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
end
