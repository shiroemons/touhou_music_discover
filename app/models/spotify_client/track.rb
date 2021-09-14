# frozen_string_literal: true

module SpotifyClient
  class Track
    def self.update_tracks(spotify_tracks)
      s_tracks = RSpotify::Track.find(spotify_tracks.map(&:spotify_id))
      s_tracks.each do |s_track|
        spotify_track = spotify_tracks.find{_1.spotify_id == s_track.id}
        spotify_track&.update(name: s_track.name)
        spotify_track&.update(payload: s_track.as_json)
      end
    end
  end
end
