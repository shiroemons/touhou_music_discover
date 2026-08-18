# frozen_string_literal: true

require 'test_helper'
require 'rake'
require 'tmpdir'

class TouhouMusicDiscoverExportTest < ActiveSupport::TestCase
  Rake::Task.define_task(:environment)
  load Rails.root.join('lib/tasks/touhou_music_discover.rake')

  SPOTIFY_EXPORT_PATH = Rails.root.join('tmp/export/spotify_touhou_music.tsv')
  TOUHOU_MUSIC_WITH_ORIGINAL_SONGS_EXPORT_PATH = Rails.root.join('tmp/export/touhou_music_with_original_songs.tsv')
  TOUHOU_MUSIC_SLIM_EXPORT_PATH = Rails.root.join('tmp/export/touhou_music_slim.tsv')

  setup do
    Rake::Task['touhou_music_discover:export:spotify'].reenable
    Rake::Task['touhou_music_discover:export:touhou_music_with_original_songs'].reenable
    Rake::Task['touhou_music_discover:export:touhou_music_slim'].reenable
    Rake::Task['touhou_music_discover:export:for_algolia'].reenable
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

    # tmp/export/ は並列ワーカープロセス間で共有されるため、自テストの出力ファイルのみを削除する
    export_path = reset_export(SPOTIFY_EXPORT_PATH)
    Rake::Task['touhou_music_discover:export:spotify'].invoke

    output = export_path.read

    assert_includes output, 'Export Active Spotify Album'
    assert_includes output, 'Export Active Spotify Track'
    assert_not_includes output, 'Export Inactive Spotify Album'
    assert_not_includes output, 'Export Inactive Spotify Track'
  end

  test 'touhou music with original songs export preloads original songs' do
    original = Original.create!(
      code: "export-original-#{SecureRandom.hex(4)}",
      title: 'Export Original',
      short_title: 'Export Original',
      original_type: 'windows',
      series_order: 1.0
    )
    original_songs = Array.new(2) do |index|
      OriginalSong.create!(
        code: "export-original-song-#{SecureRandom.hex(4)}",
        original:,
        title: "Export Original Song #{index + 1}",
        track_number: index + 1
      )
    end
    album = Album.create!(jan_code: "export-original-songs-#{SecureRandom.hex(4)}", is_touhou: true)
    tracks = Array.new(2) do |index|
      Track.create!(album:, isrc: "JPDEF#{SecureRandom.alphanumeric(7).upcase}").tap do |track|
        track.original_songs << original_songs[index]
      end
    end

    # tmp/export/ は並列ワーカープロセス間で共有されるため、自テストの出力ファイルのみを削除する
    export_path = reset_export(TOUHOU_MUSIC_WITH_ORIGINAL_SONGS_EXPORT_PATH)
    original_song_queries = count_original_song_selects do
      Rake::Task['touhou_music_discover:export:touhou_music_with_original_songs'].invoke
    end

    output = export_path.read

    tracks.each { |track| assert_includes output, track.isrc }
    original_songs.each { |original_song| assert_includes output, original_song.title }
    assert_operator original_song_queries, :<=, 1
  end

  test 'slim export uses one normalized title source for the album' do
    album = Album.create!(jan_code: "export-slim-#{SecureRandom.hex(4)}", is_touhou: true)
    track = Track.create!(album:, isrc: "JPGHI#{SecureRandom.alphanumeric(7).upcase}")
    spotify_album = create_spotify_album(album:,
                                         spotify_id: 'export-slim-spotify-album',
                                         name: 'English Collection',
                                         active: true)
    apple_album = AppleMusicAlbum.create!(
      album:,
      apple_music_id: 'export-slim-apple-album',
      name: '日本語コレクション',
      label: Album::TOUHOU_MUSIC_LABEL,
      total_tracks: 1,
      payload: {}
    )
    create_spotify_track(album:, track:, spotify_album:, spotify_id: 'export-slim-spotify-track', name: 'English Track')
    AppleMusicTrack.create!(
      album:,
      track:,
      apple_music_album: apple_album,
      apple_music_id: 'export-slim-apple-track',
      artist_name: '',
      composer_name: '',
      name: '日本語曲',
      label: Album::TOUHOU_MUSIC_LABEL,
      disc_number: 1,
      track_number: 1,
      payload: {}
    )

    export_path = reset_export(TOUHOU_MUSIC_SLIM_EXPORT_PATH)
    Rake::Task['touhou_music_discover:export:touhou_music_slim'].invoke

    output = export_path.read

    assert_includes output, "日本語コレクション\t1\t日本語曲"
    assert_not_includes output, 'English Collection'
    assert_not_includes output, 'English Track'
  end

  test 'Algolia export includes selected albums even when their tracks are stale' do
    album = Album.create!(jan_code: "export-algolia-stale-#{SecureRandom.hex(4)}", is_touhou: true)
    track = Track.create!(album:, isrc: "JPKLM#{SecureRandom.alphanumeric(7).upcase}")
    spotify_album = create_spotify_album(
      album:,
      spotify_id: 'export-algolia-stale-spotify-album',
      name: 'Export Algolia Stale Album',
      active: true
    )
    spotify_track = create_spotify_track(
      album:,
      track:,
      spotify_album:,
      spotify_id: 'export-algolia-stale-spotify-track',
      name: 'Export Algolia Stale Spotify Track'
    )
    apple_music_album = AppleMusicAlbum.create!(
      album:,
      apple_music_id: 'export-algolia-stale-apple-album',
      name: 'Export Algolia Stale Album',
      label: Album::TOUHOU_MUSIC_LABEL,
      total_tracks: 1,
      payload: { 'attributes' => {} }
    )
    apple_music_track = AppleMusicTrack.create!(
      album:,
      track:,
      apple_music_album:,
      apple_music_id: 'export-algolia-stale-apple-track',
      name: 'Export Algolia Stale Apple Track',
      label: Album::TOUHOU_MUSIC_LABEL,
      url: 'https://music.apple.com/jp/song/export-algolia-stale',
      disc_number: 1,
      track_number: 1,
      payload: {}
    )
    line_music_album = LineMusicAlbum.create!(
      album:,
      line_music_id: 'export-algolia-stale-line-album',
      name: 'Export Algolia Stale Album',
      total_tracks: 1,
      payload: { 'artists' => [] }
    )
    line_music_track = LineMusicTrack.create!(
      album:,
      track:,
      line_music_album:,
      line_music_id: 'export-algolia-stale-line-track',
      name: 'Export Algolia Stale LINE Track',
      url: 'https://music.line.me/webapp/track/export-algolia-stale',
      disc_number: 1,
      track_number: 1,
      payload: {}
    )

    stale_at = 2.months.ago
    [spotify_track, apple_music_track, line_music_track].each do |service_track|
      service_track.assign_attributes(updated_at: stale_at)
      service_track.save!(touch: false)
    end

    Dir.mktmpdir('algolia-export-test') do |directory|
      with_env('JAN_CODES' => album.jan_code, 'ALGOLIA_OUTPUT_DIR' => directory) do
        capture_io { Rake::Task['touhou_music_discover:export:for_algolia'].invoke }
      end

      {
        'touhou_music_spotify_for_algolia.json' => 'Export Algolia Stale Spotify Track',
        'touhou_music_apple_music_for_algolia.json' => 'Export Algolia Stale Apple Track',
        'touhou_music_line_music_for_algolia.json' => 'Export Algolia Stale LINE Track'
      }.each do |filename, track_name|
        rows = JSON.parse(File.read(File.join(directory, filename)))
        object_ids = rows.map { |row| row.fetch('objectID') }
        track_names = rows.first.fetch('tracks').map { |row| row.fetch('name') }

        assert_equal [album.id], object_ids
        assert_equal [track_name], track_names
      end
    end
  end

  test 'Algolia export rejects unknown JAN codes before writing files' do
    Dir.mktmpdir('algolia-export-invalid-test') do |directory|
      error = with_env('JAN_CODES' => 'missing-jAN-code', 'ALGOLIA_OUTPUT_DIR' => directory) do
        assert_raises(ArgumentError) do
          Rake::Task['touhou_music_discover:export:for_algolia'].invoke
        end
      end

      assert_empty Dir.children(directory)
      assert_match 'missing-jAN-code', error.message
    end
  end

  test 'Algolia full export includes albums whose tracks are stale' do
    album = Album.create!(jan_code: "export-algolia-full-#{SecureRandom.hex(4)}", is_touhou: true)
    track = Track.create!(album:, isrc: "JPMNO#{SecureRandom.alphanumeric(7).upcase}")
    spotify_album = create_spotify_album(
      album:,
      spotify_id: 'export-algolia-full-spotify-album',
      name: 'Export Algolia Full Album',
      active: true
    )
    spotify_track = create_spotify_track(
      album:,
      track:,
      spotify_album:,
      spotify_id: 'export-algolia-full-spotify-track',
      name: 'Export Algolia Full Track'
    )
    spotify_track.assign_attributes(updated_at: 2.months.ago)
    spotify_track.save!(touch: false)

    Dir.mktmpdir('algolia-full-export-test') do |directory|
      with_env('FULL_EXPORT' => '1', 'ALGOLIA_OUTPUT_DIR' => directory) do
        capture_io { Rake::Task['touhou_music_discover:export:for_algolia'].invoke }
      end

      rows = JSON.parse(File.read(File.join(directory, 'touhou_music_spotify_for_algolia.json')))
      object_ids = rows.map { |row| row.fetch('objectID') }

      assert_includes object_ids, album.id
    end
  end

  private

  def count_original_song_selects(&)
    count = 0
    subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
      sql = payload[:sql]
      count += 1 if sql.start_with?('SELECT') && sql.include?('FROM "original_songs"')
    end

    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record', &)
    count
  end

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

  # テストDBはRailsがワーカーごとに分離するが、tmp/export/ は分離されず全ワーカープロセスで共有される。
  # そのため setup で全出力ファイルを消すと他テストの出力を消してしまい競合するので、
  # 各テストが自分の使うパスだけをrake実行直前にリセットする。
  def reset_export(path)
    FileUtils.rm_f(path)
    path
  end

  def with_env(overrides)
    previous = overrides.keys.index_with { |key| ENV.fetch(key, nil) }
    overrides.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end
end
