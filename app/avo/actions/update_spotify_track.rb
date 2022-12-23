# frozen_string_literal: true

class UpdateSpotifyTrack < Avo::BaseAction
  self.name = 'Update spotify track'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    count = 0
    max_count = SpotifyTrack.count
    SpotifyTrack.eager_load(:album, :spotify_album, :track).find_in_batches(batch_size: 50) do |spotify_tracks|
      Retryable.retryable(tries: 5, sleep: 15, on: [RestClient::TooManyRequests, RestClient::InternalServerError]) do |retries, exception|
        warn "try #{retries} failed with exception: #{exception}" if retries.positive?

        SpotifyClient::Track.update_tracks(spotify_tracks)
      end
      count += spotify_tracks.size
      inform "Spotify 楽曲: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"
      sleep 0.5
    end

    succeed 'Done!'
    reload
  end
end
