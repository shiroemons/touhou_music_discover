# frozen_string_literal: true

module SpotifyClient
  class Track
    def self.update_tracks(spotify_tracks)
      backend.update_tracks(spotify_tracks)
    end

    def self.backend
      NativeBackend
    end
    private_class_method :backend
  end
end
