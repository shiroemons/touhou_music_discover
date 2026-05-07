# frozen_string_literal: true

require 'test_helper'

class LineMusicAlbumTest < ActiveSupport::TestCase
  LineMusicApiArtist = Struct.new(:artist_name, keyword_init: true)
  StreamingAlbum = Struct.new(:album_id, :name, :release_date, :total_tracks, :artist_name, :album, keyword_init: true)
  LineMusicApiAlbum = Struct.new(:album_id, :album_title, :release_date, :track_total_count, :artists, keyword_init: true) do
    def as_json(*)
      {
        'album_id' => album_id,
        'album_title' => album_title,
        'release_date' => release_date,
        'track_total_count' => track_total_count
      }
    end
  end

  test 'save_album stores fetched LINE MUSIC album metadata' do
    album = Album.create!(jan_code: "line-music-save-#{SecureRandom.hex(4)}")
    release_date = Date.new(2026, 2, 21)
    lm_album = build_line_music_api_album(
      album_id: 'mb-test-save',
      album_title: 'リジッドパラダイス ~ Reanimate',
      release_date:,
      track_total_count: 2
    )

    assert_difference -> { LineMusicAlbum.unscoped.count }, 1 do
      @line_music_album = LineMusicAlbum.save_album(album.id, lm_album)
    end

    assert_equal album.id, @line_music_album.album_id
    assert_equal 'mb-test-save', @line_music_album.line_music_id
    assert_equal 'リジッドパラダイス ~ Reanimate', @line_music_album.name
    assert_equal 'https://music.line.me/webapp/album/mb-test-save', @line_music_album.url
    assert_equal release_date, @line_music_album.release_date
    assert_equal 2, @line_music_album.total_tracks
    assert_equal 'リジッドパラダイス ~ Reanimate', @line_music_album.payload['album_title']
  end

  test 'save_album skips LINE MUSIC album without title' do
    album = Album.create!(jan_code: "line-music-blank-title-#{SecureRandom.hex(4)}")
    lm_album = build_line_music_api_album(album_id: 'mb-test-blank-title', album_title: nil)

    assert_no_difference -> { LineMusicAlbum.unscoped.count } do
      assert_nil LineMusicAlbum.save_album(album.id, lm_album)
    end
  end

  test 'reports progress while updating LINE MUSIC album info' do
    album = Album.create!(jan_code: "line-music-progress-#{SecureRandom.hex(4)}")
    line_music_album = LineMusicAlbum.create!(
      album:,
      line_music_id: 'mb-test-progress',
      name: 'Old Title',
      url: nil,
      total_tracks: 1,
      payload: {}
    )
    fetched_album = build_line_music_api_album(
      album_id: line_music_album.line_music_id,
      album_title: 'Updated Title',
      release_date: Date.new(2026, 2, 21),
      track_total_count: 2
    )
    updates = []

    with_parallel_each_running_inline do
      stub_line_music_album_find(fetched_album) do
        LineMusicAlbum.unscoped.where(id: line_music_album.id).scoping do
          LineMusicAlbum.update_line_music_album_info(
            progress_callback: ->(**attrs) { updates << attrs }
          )
        end
      end
    end

    assert_equal(
      { current: 0, total: 1, message: 'LINE MUSICアルバム情報を更新しています', reset: true },
      updates.first
    )
    assert_equal 1, updates.last.fetch(:current)
    assert_equal 1, updates.last.fetch(:total)
    assert_equal 'Updated Title', line_music_album.reload.name
  end

  test 'does not match same title and track count when artist and release date differ' do
    source_album = Album.create!(jan_code: "line-music-mismatch-#{SecureRandom.hex(4)}")
    streaming_album = build_streaming_album(
      source_album:,
      name: 'Chasing Rain',
      artist_name: 'DiGiTAL WiNG',
      release_date: Date.new(2026, 5, 4),
      total_tracks: 2
    )
    line_music_album = build_line_music_api_album(
      album_title: 'Chasing Rain',
      artist_names: ['Montage Whisky'],
      release_date: Date.new(2025, 11, 24),
      track_total_count: 2
    )

    assert_not LineMusicAlbum.matches_album?(line_music_album, streaming_album)
  end

  test 'matches same title and track count when artist matches even if release date differs' do
    source_album = Album.create!(jan_code: "line-music-artist-match-#{SecureRandom.hex(4)}")
    streaming_album = build_streaming_album(
      source_album:,
      name: 'Stargaze',
      artist_name: 'XL Project',
      release_date: Date.new(2025, 7, 7),
      total_tracks: 1
    )
    line_music_album = build_line_music_api_album(
      album_title: 'Stargaze',
      artist_names: ['XL Project'],
      release_date: Date.new(2025, 6, 18),
      track_total_count: 1
    )

    assert LineMusicAlbum.matches_album?(line_music_album, streaming_album)
  end

  test 'matches same title and track count when release date matches' do
    source_album = Album.create!(jan_code: "line-music-date-match-#{SecureRandom.hex(4)}")
    streaming_album = build_streaming_album(
      source_album:,
      name: 'Edge',
      artist_name: '舞音KAGURA & KOTOHGE MAI',
      release_date: Date.new(2018, 12, 30),
      total_tracks: 6
    )
    line_music_album = build_line_music_api_album(
      album_title: 'Edge',
      artist_names: ['Various Artists'],
      release_date: Date.new(2018, 12, 30),
      track_total_count: 6
    )

    assert LineMusicAlbum.matches_album?(line_music_album, streaming_album)
  end

  test 'matches title when streaming album has a subtitle and release date matches' do
    source_album = Album.create!(jan_code: "line-music-subtitle-match-#{SecureRandom.hex(4)}")
    streaming_album = build_streaming_album(
      source_album:,
      name: '東方風櫻宴 (Phantasmagoria mystical expectation)',
      artist_name: 'IOSYS',
      release_date: Date.new(2006, 5, 21),
      total_tracks: 11
    )
    line_music_album = build_line_music_api_album(
      album_title: '東方風櫻宴',
      artist_names: ['IOSYS'],
      release_date: Date.new(2006, 5, 21),
      track_total_count: 11
    )

    assert LineMusicAlbum.matches_album?(line_music_album, streaming_album)
  end

  test 'matches special title notation when artist and release date match' do
    source_album = Album.create!(jan_code: "line-music-special-title-match-#{SecureRandom.hex(4)}")
    streaming_album = build_streaming_album(
      source_album:,
      name: '🤞',
      artist_name: 'askey',
      release_date: Date.new(2024, 5, 3),
      total_tracks: 4
    )
    line_music_album = build_line_music_api_album(
      album_title: ':crossed_finger:',
      artist_names: ['askey'],
      release_date: Date.new(2024, 5, 3),
      track_total_count: 4
    )

    assert LineMusicAlbum.matches_album?(line_music_album, streaming_album)
  end

  private

  def build_line_music_api_album(artist_names: [], **)
    LineMusicApiAlbum.new(
      artists: artist_names.map { |artist_name| LineMusicApiArtist.new(artist_name:) },
      **
    )
  end

  def build_streaming_album(source_album:, **attributes)
    StreamingAlbum.new(album_id: source_album.id, album: source_album, **attributes)
  end

  def stub_line_music_album_find(fetched_album)
    original_method = LineMusic::Album.method(:find)

    LineMusic::Album.define_singleton_method(:find) { |_id| fetched_album }
    yield
  ensure
    LineMusic::Album.define_singleton_method(:find, original_method)
  end

  def with_parallel_each_running_inline
    original_method = Parallel.method(:each)

    Parallel.define_singleton_method(:each) do |items, options = {}, &block|
      items.each_with_index do |item, index|
        result = block.call(item)
        options[:finish]&.call(item, index, result)
      end
    end
    yield
  ensure
    Parallel.define_singleton_method(:each, original_method)
  end
end
