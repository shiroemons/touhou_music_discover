# frozen_string_literal: true

module SpotifyClient
  class AudioFeatures
    # SpotifyApi (lib/spotify_api) 経由でオーディオ特性を取得する新経路。
    class NativeBackend
      def self.fetch_by_spotify_tracks(spotify_tracks)
        track_afs = SpotifyApi::AudioFeatures.find_many(spotify_tracks.map(&:spotify_id))
        tracks_by_spotify_id = spotify_tracks.index_by(&:spotify_id)
        track_afs.each do |track_af|
          spotify_track = tracks_by_spotify_id[track_af&.id]
          next if spotify_track.blank? || track_af.blank?

          SpotifyTrackAudioFeature.save_audio_features(spotify_track, track_af)
        end
      rescue *SpotifyRetry::RATE_LIMIT_ERRORS => e
        SpotifyRateLimit.record_from_error!(e, source: 'SpotifyClient::AudioFeatures.fetch_by_spotify_tracks')
        raise
      end
    end
  end
end
