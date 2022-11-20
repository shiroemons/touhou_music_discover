# frozen_string_literal: true

class UpdateSpotifyAlbum < Avo::BaseAction
  self.name = 'Update spotify album'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    count = 0
    max_count = SpotifyAlbum.count
    SpotifyAlbum.eager_load(:album).find_in_batches(batch_size: 20) do |spotify_albums|
      Retryable.retryable(tries: 5, sleep: 15, on: [RestClient::TooManyRequests, RestClient::InternalServerError]) do |retries, exception|
        warn "try #{retries} failed with exception: #{exception}" if retries.positive?

        SpotifyClient::Album.update_albums(spotify_albums)
      end
      count += spotify_albums.size
      inform "Spotify アルバム: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"
      sleep 0.5
    end
  end
end
