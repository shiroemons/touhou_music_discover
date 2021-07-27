# frozen_string_literal: true

namespace :spotify do
  desc 'Spotify MasterArtistからアーティスト情報を取得'
  task master_artist_fetch: :environment do
    artists = MasterArtist.spotify
    master_artist_count = 0
    max_master_artist_count = artists.count
    artists.each do |artist|
      SpotifyClient::Artist.fetch(artist.key) unless SpotifyArtist.exists?(spotify_id: artist.key)
      master_artist_count += 1
      print "\rマスターアーティスト: #{master_artist_count}/#{max_master_artist_count} Progress: #{(master_artist_count * 100.0 / max_master_artist_count).round(1)}%"
    end
  end

  desc 'Spotify SpotifyTrackからアーティスト情報を取得'
  task spotify_track_artist_fetch: :environment do
    SpotifyTrack.find_each do |spotify_track|
      payload = spotify_track.payload
      payload['artists']&.each do |artist|
        artist_id = artist['id']
        SpotifyClient::Artist.fetch(artist_id) unless SpotifyArtist.exists?(spotify_id: artist_id)
      end
    end
  end

  desc 'Spotify アーティストに紐づくアルバム情報とトラック情報を取得'
  task artists_album_and_tracks_fetch: :environment do
    spotify_artists = SpotifyArtist.all
    spotify_artist_count = 0
    max_spotify_artist_count = spotify_artists.count
    print "\rSpotifyアーティスト: #{spotify_artist_count}/#{max_spotify_artist_count} Progress: #{(spotify_artist_count * 100.0 / max_spotify_artist_count).round(1)}%"
    spotify_artists.each do |spotify_artist|
      SpotifyClient::Album.fetch_artists_albums_tracks(spotify_artist.spotify_id)
      spotify_artist_count += 1
      print "\rSpotifyアーティスト: #{spotify_artist_count}/#{max_spotify_artist_count} Progress: #{(spotify_artist_count * 100.0 / max_spotify_artist_count).round(1)}%"
    end
  end
end
