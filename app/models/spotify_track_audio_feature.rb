# frozen_string_literal: true

class SpotifyTrackAudioFeature < ApplicationRecord
  belongs_to :track
  belongs_to :spotify_track

  def self.save_audio_features(spotify_track, track_af)
    return nil if spotify_track.blank? || track_af.blank?

    st_audio_features = SpotifyTrackAudioFeature.find_or_create_by!(spotify_track_id: spotify_track.id) do |record|
      record.track_id = spotify_track.track_id
      record.spotify_id = spotify_track.spotify_id
      record.acousticness = track_af.acousticness
      record.danceability = track_af.danceability
      record.duration_ms = track_af.duration_ms
      record.energy = track_af.energy
      record.instrumentalness = track_af.instrumentalness
      record.key = track_af.key
      record.liveness = track_af.liveness
      record.loudness = track_af.loudness
      record.mode = track_af.mode
      record.speechiness = track_af.speechiness
      record.tempo = track_af.tempo
      record.time_signature = track_af.time_signature
      record.valence = track_af.valence
    end

    st_audio_features.update(
      track_id: spotify_track.track_id,
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
      valence: track_af.valence,
      analysis_url: track_af.analysis_url.to_s,
      payload: track_af.as_json
    )
    st_audio_features
  end
end
