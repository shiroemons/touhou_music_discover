# frozen_string_literal: true

module SpotifyClient
  class AudioFeatures
    def self.fetch_by_spotify_tracks(spotify_tracks)
      track_afs = RSpotify::AudioFeatures.find(spotify_tracks.map(&:spotify_id))
      track_afs.each do |track_af|
        spotify_track = spotify_tracks.find {_1.spotify_id == track_af&.id}
        next if spotify_track.blank? || track_af.blank?

        SpotifyTrackAudioFeature.save_audio_features(spotify_track, track_af)
      end
    end
  end
end
