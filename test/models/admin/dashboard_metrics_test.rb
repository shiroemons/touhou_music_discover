# frozen_string_literal: true

require 'test_helper'

module Admin
  class DashboardMetricsTest < ActiveSupport::TestCase
    test 'summarizes streaming coverage, work queue, data quality, and playlist sync' do
      album_with_spotify = Album.create!(jan_code: '4980000000001')
      album_without_spotify = Album.create!(jan_code: '4980000000002')
      track_with_spotify = Track.create!(album: album_with_spotify, jan_code: album_with_spotify.jan_code, isrc: 'JPABC2600001')
      track_without_spotify = Track.create!(album: album_without_spotify, jan_code: album_without_spotify.jan_code, isrc: 'JPABC2600002')
      spotify_album = SpotifyAlbum.create!(
        album: album_with_spotify,
        spotify_id: 'spotify-album-1',
        album_type: 'album',
        name: 'Spotify Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        total_tracks: 2
      )
      SpotifyTrack.create!(
        album: album_with_spotify,
        track: track_with_spotify,
        spotify_album:,
        spotify_id: 'spotify-track-1',
        name: 'Spotify Track',
        label: Album::TOUHOU_MUSIC_LABEL
      )
      SpotifyPlaylist.create!(
        spotify_id: 'playlist-1',
        spotify_user_id: 'user-1',
        name: 'Fresh Playlist',
        synced_at: 1.hour.ago
      )
      SpotifyPlaylist.create!(
        spotify_id: 'playlist-2',
        spotify_user_id: 'user-1',
        name: 'Never Synced Playlist'
      )

      metrics = Admin::DashboardMetrics.call
      spotify_coverage = metrics.fetch(:service_coverages).find { |coverage| coverage.fetch(:key) == :spotify }

      assert_equal 2, metrics.dig(:totals, :albums)
      assert_equal 2, metrics.dig(:totals, :tracks)
      assert_equal 1, spotify_coverage.fetch(:album_count)
      assert_equal 1, spotify_coverage.fetch(:album_missing_count)
      assert_equal 50.0, spotify_coverage.fetch(:album_coverage_percent)
      assert_equal 1, spotify_coverage.fetch(:track_count)
      assert_equal 1, spotify_coverage.fetch(:track_missing_count)
      assert_equal 1, spotify_coverage.fetch(:incomplete_album_tracks_count)
      assert_equal 'spotify_tracks', spotify_coverage.fetch(:missing_track_action_resource_key)
      assert_equal 'fetch_missing_spotify_tracks', spotify_coverage.fetch(:missing_track_action_key)
      missing_track_sample_ids = spotify_coverage.fetch(:missing_track_samples).map { |track| track.fetch(:id) }
      assert_equal [track_without_spotify.id], missing_track_sample_ids
      assert_includes metrics.fetch(:work_queue).map { |item| item.fetch(:key) }, 'spotify_missing_albums'
      assert_includes metrics.fetch(:data_quality).map { |item| item.fetch(:key) }, 'spotify_tracks_missing_audio_features'
      assert_equal 2, metrics.dig(:playlist_sync, :total)
      assert_equal 1, metrics.dig(:playlist_sync, :stale)
      assert_equal 50.0, metrics.dig(:playlist_sync, :stale_percent)
    end

    test 'does not round incomplete coverage up to 100 percent' do
      metrics = Admin::DashboardMetrics.new

      assert_equal 99.8, metrics.send(:percentage, 3685, 3691)
      assert_equal 100.0, metrics.send(:percentage, 3691, 3691)
    end
  end
end
