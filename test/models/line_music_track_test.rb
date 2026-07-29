# frozen_string_literal: true

require 'test_helper'

class LineMusicTrackTest < ActiveSupport::TestCase
  SourceTrack = Struct.new(:album_id, :track_id, :name, :disc_number, :track_number, keyword_init: true)

  LineMusicApiTrack = Struct.new(:track_id, :track_title, :disc_number, :track_number, keyword_init: true) do
    def as_json(*)
      { 'track_id' => track_id, 'track_title' => track_title, 'artists' => [] }
    end
  end

  test 'save_track reuses the row with the same line_music_album_id and line_music_id when other attributes differ' do
    album, track, line_music_album = create_line_music_album
    line_music_id = "lm-track-#{SecureRandom.hex(4)}"

    assert_difference -> { LineMusicTrack.unscoped.count }, 1 do
      LineMusicTrack.save_track(
        album.id,
        track.id,
        line_music_album,
        build_api_track(track_id: line_music_id, track_title: '妖々跋扈 ~ Who done it!')
      )
    end

    assert_no_difference -> { LineMusicTrack.unscoped.count } do
      LineMusicTrack.save_track(
        album.id,
        track.id,
        line_music_album,
        build_api_track(track_id: line_music_id, track_title: '妖々跋扈 ~ Who done it', track_number: 4)
      )
    end

    line_music_track = LineMusicTrack.unscoped.find_by!(line_music_album_id: line_music_album.id, line_music_id:)

    assert_equal '妖々跋扈 ~ Who done it', line_music_track.name
    assert_equal 4, line_music_track.track_number
  end

  test 'reports progress while fetching LINE MUSIC tracks' do
    album = Album.create!(jan_code: "line-music-track-progress-#{SecureRandom.hex(4)}")
    updates = []
    processed_albums = []

    with_line_music_track_processor(->(processed_album) { processed_albums << processed_album }) do
      Album.unscoped.where(id: album.id).scoping do
        LineMusicTrack.fetch_tracks(progress_callback: ->(**attrs) { updates << attrs })
      end
    end

    assert_equal [album], processed_albums
    assert_equal(
      { current: 0, total: 1, message: 'LINE MUSICトラックを取得しています', reset: true },
      updates.first
    )
    assert_equal 1, updates.last.fetch(:current)
    assert_equal 1, updates.last.fetch(:total)
    assert_equal "LINE MUSICトラックを処理しています: #{album.jan_code}", updates.last.fetch(:message)
  end

  test 'process_album maps a shifted LINE MUSIC catalog by unique titles without positional mistakes' do
    album, source_tracks, line_music_album = create_apple_music_catalog(
      track_titles: ['一曲目', 'LINE MUSICにない曲', '三曲目', '四曲目'],
      line_total_tracks: 3
    )
    line_tracks = [
      build_api_track(track_id: 'lm-shifted-1', track_title: '一曲目', track_number: 1),
      build_api_track(track_id: 'lm-shifted-3', track_title: '三曲目', track_number: 2),
      build_api_track(track_id: 'lm-shifted-4', track_title: '四曲目', track_number: 3)
    ]

    with_line_music_album_tracks(line_tracks) do
      LineMusicTrack.process_album(album)
    end

    saved_tracks = LineMusicTrack.unscoped.where(line_music_album:).index_by(&:line_music_id)

    assert_equal 3, saved_tracks.size
    assert_equal source_tracks.fetch(0).track_id, saved_tracks.fetch('lm-shifted-1').track_id
    assert_equal source_tracks.fetch(2).track_id, saved_tracks.fetch('lm-shifted-3').track_id
    assert_equal source_tracks.fetch(3).track_id, saved_tracks.fetch('lm-shifted-4').track_id
    assert_not_includes saved_tracks.values.map(&:track_id), source_tracks.fetch(1).track_id
  end

  test 'process_album does not fall back to positions when catalog counts differ and titles do not match' do
    album, _source_tracks, line_music_album = create_apple_music_catalog(
      track_titles: ['English title one', 'English title two'],
      line_total_tracks: 1
    )
    line_tracks = [
      build_api_track(track_id: 'lm-unsafe-position', track_title: '日本語タイトル', track_number: 1)
    ]

    with_line_music_album_tracks(line_tracks) do
      LineMusicTrack.process_album(album)
    end

    assert_empty LineMusicTrack.unscoped.where(line_music_album:)
  end

  test 'build_track_mappings preserves positional fallback for complete equal-sized translated catalogs' do
    source_tracks = [
      build_source_track(track_id: 'source-1', name: 'English one', track_number: 1),
      build_source_track(track_id: 'source-2', name: 'English two', track_number: 2)
    ]
    line_tracks = [
      build_api_track(track_id: 'line-1', track_title: '日本語一', track_number: 1),
      build_api_track(track_id: 'line-2', track_title: '日本語二', track_number: 2)
    ]
    source_sets = [{ service: :spotify, tracks: source_tracks, declared_total: 2, fallback_priority: 1 }]

    mappings = LineMusicTrack.build_track_mappings(source_sets, line_tracks)

    assert_equal(
      [
        ['source-1', 'line-1', :position],
        ['source-2', 'line-2', :position]
      ],
      mappings.map { |mapping| [mapping.fetch(:source).track_id, mapping.fetch(:line).track_id, mapping.fetch(:strategy)] }
    )
  end

  test 'build_track_mappings disables positional fallback when an exact title proves the order differs' do
    source_tracks = [
      build_source_track(track_id: 'source-translated', name: 'English title', track_number: 1),
      build_source_track(track_id: 'source-anchor', name: '共通タイトル', track_number: 2)
    ]
    line_tracks = [
      build_api_track(track_id: 'line-anchor', track_title: '共通タイトル', track_number: 1),
      build_api_track(track_id: 'line-translated', track_title: '日本語タイトル', track_number: 2)
    ]
    source_sets = [{ service: :spotify, tracks: source_tracks, declared_total: 2, fallback_priority: 1 }]

    mappings = LineMusicTrack.build_track_mappings(source_sets, line_tracks)

    assert_equal(
      [['source-anchor', 'line-anchor', :title]],
      mappings.map { |mapping| [mapping.fetch(:source).track_id, mapping.fetch(:line).track_id, mapping.fetch(:strategy)] }
    )
  end

  test 'build_track_mappings skips duplicate titles instead of guessing' do
    source_tracks = [
      build_source_track(track_id: 'source-duplicate-1', name: '同名曲', track_number: 1),
      build_source_track(track_id: 'source-duplicate-2', name: '同名曲', track_number: 2)
    ]
    line_tracks = [
      build_api_track(track_id: 'line-duplicate', track_title: '同名曲', track_number: 1)
    ]
    source_sets = [{ service: :apple_music, tracks: source_tracks, declared_total: 2, fallback_priority: 0 }]

    assert_empty LineMusicTrack.build_track_mappings(source_sets, line_tracks)
  end

  private

  def create_line_music_album
    jan_code = "line-music-track-save-#{SecureRandom.hex(4)}"
    album = Album.create!(jan_code:)
    track = Track.create!(jan_code:, isrc: "ISRC#{SecureRandom.hex(4)}")
    line_music_album = LineMusicAlbum.create!(
      album:,
      line_music_id: "lm-album-#{SecureRandom.hex(4)}",
      name: 'LINE MUSIC Album',
      total_tracks: 2,
      payload: {}
    )

    [album, track, line_music_album]
  end

  def build_api_track(**attributes)
    LineMusicApiTrack.new(track_title: 'LINE MUSIC Track', disc_number: 1, track_number: 1, **attributes)
  end

  def build_source_track(**attributes)
    SourceTrack.new(album_id: 'album-id', name: 'Source Track', disc_number: 1, track_number: 1, **attributes)
  end

  def create_apple_music_catalog(track_titles:, line_total_tracks:)
    jan_code = "line-music-track-match-#{SecureRandom.hex(4)}"
    album = Album.create!(jan_code:)
    apple_music_album = AppleMusicAlbum.create!(
      album:,
      apple_music_id: "apple-album-#{SecureRandom.hex(4)}",
      name: 'Apple Music Album',
      label: Album::TOUHOU_MUSIC_LABEL,
      total_tracks: track_titles.size,
      payload: {}
    )
    apple_music_tracks = track_titles.each_with_index.map do |title, index|
      track = Track.create!(album:, isrc: "ISRC#{SecureRandom.hex(6)}")
      AppleMusicTrack.create!(
        album:,
        track:,
        apple_music_album:,
        apple_music_id: "apple-track-#{SecureRandom.hex(6)}",
        name: title,
        label: Album::TOUHOU_MUSIC_LABEL,
        url: '',
        disc_number: 1,
        track_number: index + 1,
        payload: {}
      )
    end
    line_music_album = LineMusicAlbum.create!(
      album:,
      line_music_id: "lm-album-#{SecureRandom.hex(4)}",
      name: 'LINE MUSIC Album',
      total_tracks: line_total_tracks,
      payload: {}
    )

    [album.reload, apple_music_tracks, line_music_album]
  end

  def with_line_music_track_processor(processor)
    singleton_class = LineMusicTrack.singleton_class
    original_method = LineMusicTrack.method(:process_album)

    singleton_class.define_method(:process_album) { |album| processor.call(album) }
    yield
  ensure
    singleton_class.define_method(:process_album, original_method)
  end

  def with_line_music_album_tracks(tracks)
    singleton_class = LineMusic::Album.singleton_class
    original_method = LineMusic::Album.method(:tracks)

    singleton_class.define_method(:tracks) { |_id, **| tracks }
    yield
  ensure
    singleton_class.define_method(:tracks, original_method)
  end
end
