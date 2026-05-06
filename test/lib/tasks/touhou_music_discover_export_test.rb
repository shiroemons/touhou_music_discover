# frozen_string_literal: true

require 'test_helper'
require 'rake'

class TouhouMusicDiscoverExportTest < ActiveSupport::TestCase
  SPOTIFY_EXPORT_PATH = Rails.root.join('tmp/export/spotify_touhou_music.tsv')

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?('touhou_music_discover:export:spotify')
    Rake::Task['touhou_music_discover:export:spotify'].reenable
    FileUtils.rm_f(SPOTIFY_EXPORT_PATH)
  end

  test 'spotify export outputs active spotify albums only' do
    active_album = Album.create!(jan_code: "export-active-spotify-#{SecureRandom.hex(4)}", is_touhou: true)
    inactive_album = Album.create!(jan_code: "export-inactive-spotify-#{SecureRandom.hex(4)}", is_touhou: true)
    active_spotify_album = create_spotify_album(album: active_album, spotify_id: 'export-active-spotify-album', name: 'Export Active Spotify Album', active: true)
    inactive_spotify_album = create_spotify_album(album: inactive_album, spotify_id: 'export-inactive-spotify-album', name: 'Export Inactive Spotify Album', active: false)
    active_track = Track.create!(album: active_album, isrc: "JPABC#{SecureRandom.alphanumeric(7).upcase}")
    inactive_track = Track.create!(album: inactive_album, isrc: "JPABC#{SecureRandom.alphanumeric(7).upcase}")
    create_spotify_track(album: active_album, track: active_track, spotify_album: active_spotify_album, spotify_id: 'export-active-spotify-track', name: 'Export Active Spotify Track')
    create_spotify_track(album: inactive_album, track: inactive_track, spotify_album: inactive_spotify_album, spotify_id: 'export-inactive-spotify-track', name: 'Export Inactive Spotify Track')

    Rake::Task['touhou_music_discover:export:spotify'].invoke

    output = SPOTIFY_EXPORT_PATH.read
    assert_includes output, 'Export Active Spotify Album'
    assert_includes output, 'Export Active Spotify Track'
    assert_not_includes output, 'Export Inactive Spotify Album'
    assert_not_includes output, 'Export Inactive Spotify Track'
  end

  private

  def create_spotify_album(album:, spotify_id:, name:, active:)
    SpotifyAlbum.create!(
      album:,
      spotify_id:,
      album_type: 'album',
      name:,
      label: Album::TOUHOU_MUSIC_LABEL,
      release_date: Date.new(2026, 5, 6),
      total_tracks: 1,
      active:,
      payload: { 'available_markets' => ['JP'] }
    )
  end

  def create_spotify_track(album:, track:, spotify_album:, spotify_id:, name:)
    SpotifyTrack.create!(
      album:,
      track:,
      spotify_album:,
      spotify_id:,
      name:,
      label: Album::TOUHOU_MUSIC_LABEL,
      disc_number: 1,
      track_number: 1,
      duration_ms: 180_000,
      payload: {}
    )
  end
end
