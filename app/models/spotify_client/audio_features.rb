# frozen_string_literal: true

module SpotifyClient
  class AudioFeatures
    def self.fetch_by_spotify_tracks(spotify_tracks)
      backend.fetch_by_spotify_tracks(spotify_tracks)
    end

    def self.backend
      NativeBackend
    end
    private_class_method :backend
  end
end
