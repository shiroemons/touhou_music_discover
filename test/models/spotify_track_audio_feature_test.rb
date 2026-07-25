# frozen_string_literal: true

require 'test_helper'

class SpotifyTrackAudioFeatureTest < ActiveSupport::TestCase
  SpotifyApiAudioFeatures = Struct.new(
    :acousticness,
    :danceability,
    :duration_ms,
    :energy,
    :instrumentalness,
    :key,
    :liveness,
    :loudness,
    :mode,
    :speechiness,
    :tempo,
    :time_signature,
    :valence,
    :analysis_url,
    keyword_init: true
  ) do
    def as_json(*)
      { 'tempo' => tempo, 'analysis_url' => analysis_url }
    end
  end

  # Spotify の再解析で tempo などが変わっても行は増やさず更新する。
  test 'save_audio_features reuses the row with the same spotify_track_id when the analysis changes' do
    spotify_track = create_spotify_track

    assert_difference -> { SpotifyTrackAudioFeature.unscoped.count }, 1 do
      SpotifyTrackAudioFeature.save_audio_features(spotify_track, build_audio_features(tempo: 174.0))
    end

    assert_no_difference -> { SpotifyTrackAudioFeature.unscoped.count } do
      @audio_feature = SpotifyTrackAudioFeature.save_audio_features(
        spotify_track,
        build_audio_features(tempo: 87.5, energy: 0.42)
      )
    end

    assert_in_delta 87.5, @audio_feature.reload.tempo
    assert_in_delta 0.42, @audio_feature.energy
  end

  test 'save_audio_features returns nil for blank arguments' do
    spotify_track = create_spotify_track

    assert_no_difference -> { SpotifyTrackAudioFeature.unscoped.count } do
      assert_nil SpotifyTrackAudioFeature.save_audio_features(nil, build_audio_features)
      assert_nil SpotifyTrackAudioFeature.save_audio_features(spotify_track, nil)
    end
  end

  private

  def create_spotify_track
    jan_code = "spotify-audio-feature-#{SecureRandom.hex(4)}"
    album = Album.create!(jan_code:)
    track = Track.create!(jan_code:, isrc: "ISRC#{SecureRandom.hex(4)}")
    spotify_album = SpotifyAlbum.create!(
      album:,
      spotify_id: "spotify-album-#{SecureRandom.hex(4)}",
      album_type: 'album',
      name: 'Spotify Album',
      label: ::Album::TOUHOU_MUSIC_LABEL,
      payload: {}
    )

    SpotifyTrack.create!(
      album:,
      track:,
      spotify_album:,
      spotify_id: "spotify-track-#{SecureRandom.hex(4)}",
      name: 'Spotify Track',
      label: ::Album::TOUHOU_MUSIC_LABEL,
      payload: {}
    )
  end

  def build_audio_features(**attributes)
    SpotifyApiAudioFeatures.new(
      acousticness: 0.1,
      danceability: 0.2,
      duration_ms: 240_000,
      energy: 0.3,
      instrumentalness: 0.4,
      key: 5,
      liveness: 0.6,
      loudness: -7.5,
      mode: 1,
      speechiness: 0.05,
      tempo: 174.0,
      time_signature: 4,
      valence: 0.8,
      analysis_url: 'https://api.spotify.com/v1/audio-analysis/test',
      **attributes
    )
  end
end
