# frozen_string_literal: true

module SpotifyClient
  class Track
    # rspotify (RSpotify::*) 経由でトラックを取得する旧経路。
    # SpotifyApi への移行完了後、Issue #563 でこのファイルごと削除する。
    class RspotifyBackend
      def self.update_tracks(spotify_tracks)
        s_tracks = ::RSpotify::Track.find(spotify_tracks.map(&:spotify_id))
        s_tracks.each do |s_track|
          spotify_track = spotify_tracks.find { it.spotify_id == s_track.id }
          spotify_track&.update(
            spotify_id: s_track.id,
            name: s_track.name,
            url: s_track.external_urls['spotify'],
            disc_number: s_track.disc_number,
            track_number: s_track.track_number,
            duration_ms: s_track.duration_ms,
            payload: s_track.as_json
          )
        end
      rescue *SpotifyRetry::RATE_LIMIT_ERRORS => e
        SpotifyRateLimit.record_from_error!(e, source: 'SpotifyClient::Track.update_tracks')
        raise
      end
    end
  end
end
