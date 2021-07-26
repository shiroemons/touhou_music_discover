# frozen_string_literal: true

namespace :spotify do
  desc 'Spotify アーティスト情報取得'
  task master_artist_fetch: :environment do
    artists = MasterArtist.spotify
    master_artist_count = 0
    max_master_artist_count = artists.count
    artists.each do |artist|
      SpotifyClient::Artist.fetch(artist.key)
      master_artist_count += 1
      print "\rマスターアーティスト: #{master_artist_count}/#{max_master_artist_count} Progress: #{(master_artist_count * 100.0 / max_master_artist_count).round(1)}%"
    end
  end

  desc 'Spotify アーティストに紐づくアルバム情報取得'
  task artists_album_fetch: :environment do
    spotify_artists = SpotifyArtist.all
    spotify_artist_count = 0
    max_spotify_artist_count = spotify_artists.count
    spotify_artists.each do |spotify_artist|
      SpotifyClient::Album.fetch_artists_albums(spotify_artist.spotify_id)
      spotify_artist_count += 1
      print "\rSpotifyアーティスト: #{spotify_artist_count}/#{max_spotify_artist_count} Progress: #{(spotify_artist_count * 100.0 / max_spotify_artist_count).round(1)}%"
    end
  end
end
