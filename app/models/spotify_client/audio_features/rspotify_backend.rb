# frozen_string_literal: true

module SpotifyClient
  class AudioFeatures
    # rspotify (RSpotify::*) 経由でオーディオ特性を取得する旧経路。
    # SpotifyApi への移行完了後、Issue #563 でこのファイルごと削除する。
    class RspotifyBackend
      def self.fetch_by_spotify_tracks(spotify_tracks)
        track_afs = ::RSpotify::AudioFeatures.find(spotify_tracks.map(&:spotify_id))
        track_afs.each do |track_af|
          spotify_track = spotify_tracks.find { it.spotify_id == track_af&.id }
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
