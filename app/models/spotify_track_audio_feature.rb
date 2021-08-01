# frozen_string_literal: true

class SpotifyTrackAudioFeature < ApplicationRecord
  belongs_to :track
  belongs_to :spotify_track

  def self.save_audio_features(spotify_track, track_af)
    return nil if spotify_track.blank? || track_af.blank?

    st_audio_features = SpotifyTrackAudioFeature.find_or_create_by!(
      track_id: spotify_track.track_id,
      spotify_track_id: spotify_track.id,
      spotify_id: spotify_track.spotify_id,
      acousticness: track_af.acousticness,
      danceability: track_af.danceability,
      duration_ms: track_af.duration_ms,
      energy: track_af.energy,
      instrumentalness: track_af.instrumentalness,
      key: track_af.key,
      liveness: track_af.liveness,
      loudness: track_af.loudness,
      mode: track_af.mode,
      speechiness: track_af.speechiness,
      tempo: track_af.tempo,
      time_signature: track_af.time_signature,
      valence: track_af.valence
    )
    st_audio_features.update(
      analysis_url: track_af.analysis_url.to_s,
      payload: track_af.as_json
    )
    st_audio_features
  end
end
