# frozen_string_literal: true

require 'test_helper'

module SpotifyClient
  class AudioFeaturesTest < ActiveSupport::TestCase
    # SpotifyTrackAudioFeature.save_audio_features が読む属性を、
    # SpotifyApi::Response がそのまま返せることを確認する。
    test 'native backend saves audio features returned as SpotifyApi::Response' do
      spotify_track = create_spotify_track
      audio_features_api, requested_ids = fake_audio_features_api(audio_features_body(spotify_track.spotify_id))

      with_native_backend do
        stub_const(SpotifyApi, :AudioFeatures, audio_features_api) do
          assert_difference -> { SpotifyTrackAudioFeature.count }, 1 do
            SpotifyClient::AudioFeatures.fetch_by_spotify_tracks([spotify_track])
          end
        end
      end

      audio_feature = SpotifyTrackAudioFeature.find_by!(spotify_track:)

      assert_equal [[spotify_track.spotify_id]], requested_ids
      assert_equal spotify_track.track_id, audio_feature.track_id
      assert_in_delta 0.12, audio_feature.acousticness
      assert_in_delta 0.34, audio_feature.danceability
      assert_equal 210_000, audio_feature.duration_ms
      assert_in_delta 0.56, audio_feature.energy
      assert_in_delta 0.78, audio_feature.instrumentalness
      assert_equal 5, audio_feature.key
      assert_in_delta 0.11, audio_feature.liveness
      assert_in_delta(-6.5, audio_feature.loudness)
      assert_equal 1, audio_feature.mode
      assert_in_delta 0.05, audio_feature.speechiness
      assert_in_delta 128.5, audio_feature.tempo
      assert_equal 4, audio_feature.time_signature
      assert_in_delta 0.65, audio_feature.valence
      assert_equal 'https://api.spotify.com/v1/audio-analysis/track-1', audio_feature.analysis_url
      assert_equal audio_features_body(spotify_track.spotify_id), audio_feature.payload
    end

    test 'native backend skips audio features that have no matching Spotify track' do
      spotify_track = create_spotify_track
      audio_features_api, _requested_ids = fake_audio_features_api(audio_features_body('unknown-track'))

      with_native_backend do
        stub_const(SpotifyApi, :AudioFeatures, audio_features_api) do
          assert_no_difference -> { SpotifyTrackAudioFeature.count } do
            SpotifyClient::AudioFeatures.fetch_by_spotify_tracks([spotify_track])
          end
        end
      end
    end

    # find_many は該当が無い ID に対して nil を返すため、nil 要素を読み飛ばす。
    test 'native backend skips nil audio features entries' do
      spotify_track = create_spotify_track
      audio_features_api, _requested_ids = fake_audio_features_api(nil, audio_features_body(spotify_track.spotify_id))

      with_native_backend do
        stub_const(SpotifyApi, :AudioFeatures, audio_features_api) do
          assert_difference -> { SpotifyTrackAudioFeature.count }, 1 do
            SpotifyClient::AudioFeatures.fetch_by_spotify_tracks([spotify_track])
          end
        end
      end

      assert_equal spotify_track.track_id, SpotifyTrackAudioFeature.find_by!(spotify_track:).track_id
    end

    private

    def create_spotify_track
      jan_code = "audio-features-#{SecureRandom.hex(4)}"
      album = ::Album.create!(jan_code:)
      spotify_album = SpotifyAlbum.create!(
        album:,
        spotify_id: "album-#{jan_code}",
        album_type: 'album',
        name: 'Audio Features Album',
        label: ::Album::TOUHOU_MUSIC_LABEL,
        total_tracks: 1,
        payload: { 'available_markets' => ['JP'] }
      )
      track = ::Track.create!(jan_code:, isrc: "ISRC-#{jan_code}")
      album.tracks << track
      SpotifyTrack.create!(
        album:,
        spotify_album:,
        track:,
        spotify_id: 'track-1',
        name: 'Track 1',
        label: spotify_album.label,
        disc_number: 1,
        track_number: 1,
        duration_ms: 210_000,
        payload: {}
      )
    end

    def audio_features_body(spotify_id)
      {
        'id' => spotify_id,
        'acousticness' => 0.12,
        'danceability' => 0.34,
        'duration_ms' => 210_000,
        'energy' => 0.56,
        'instrumentalness' => 0.78,
        'key' => 5,
        'liveness' => 0.11,
        'loudness' => -6.5,
        'mode' => 1,
        'speechiness' => 0.05,
        'tempo' => 128.5,
        'time_signature' => 4,
        'valence' => 0.65,
        'analysis_url' => 'https://api.spotify.com/v1/audio-analysis/track-1'
      }
    end

    def fake_audio_features_api(*bodies)
      requested_ids = []

      klass = Class.new do
        define_singleton_method(:find_many) do |ids|
          requested_ids << ids
          SpotifyApi::Response.build(bodies)
        end
      end

      [klass, requested_ids]
    end

    def with_native_backend
      original = SpotifyApi.config.native_client_enabled
      SpotifyApi.config.native_client_enabled = true
      yield
    ensure
      SpotifyApi.config.native_client_enabled = original
    end
  end
end
