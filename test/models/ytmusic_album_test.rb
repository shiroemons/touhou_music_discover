# frozen_string_literal: true

require 'test_helper'

class YtmusicAlbumTest < ActiveSupport::TestCase
  YtmusicApiAlbum = Struct.new(:title, :playlist_url, :track_total_count, :year, :degraded, :playable_track_count,
                               keyword_init: true) do
    def as_json(*)
      { 'title' => title, 'year' => year, 'artists' => [] }
    end

    def degraded?
      degraded
    end
  end

  test 'save_album reuses the row with the same album_id and browse_id when other attributes differ' do
    album = Album.create!(jan_code: "ytmusic-album-save-#{SecureRandom.hex(4)}")
    browse_id = "MPREb_#{SecureRandom.hex(4)}"

    assert_difference -> { YtmusicAlbum.unscoped.count }, 1 do
      YtmusicAlbum.save_album(album.id, browse_id, build_api_album(title: '東方猫鍵盤'))
    end

    assert_no_difference -> { YtmusicAlbum.unscoped.count } do
      @ytmusic_album = YtmusicAlbum.save_album(
        album.id,
        browse_id,
        build_api_album(title: '東方猫鍵盤 9', track_total_count: 12)
      )
    end

    assert_equal '東方猫鍵盤 9', @ytmusic_album.reload.name
    assert_equal 12, @ytmusic_album.total_tracks
    assert_equal "https://music.youtube.com/browse/#{browse_id}", @ytmusic_album.url
  end

  test 'save_album does not create a record when the album is degraded' do
    album = Album.create!(jan_code: "ytmusic-album-degraded-save-#{SecureRandom.hex(4)}")
    browse_id = "MPREb_#{SecureRandom.hex(4)}"

    result = nil
    assert_no_difference -> { YtmusicAlbum.unscoped.count } do
      result = YtmusicAlbum.save_album(album.id, browse_id, build_api_album(degraded: true))
    end

    assert_nil result
    assert_not YtmusicAlbum.unscoped.exists?(browse_id:)
  end

  test 'save_album creates a record as usual when the album is not degraded' do
    album = Album.create!(jan_code: "ytmusic-album-normal-save-#{SecureRandom.hex(4)}")
    browse_id = "MPREb_#{SecureRandom.hex(4)}"

    result = nil
    assert_difference -> { YtmusicAlbum.unscoped.count }, 1 do
      result = YtmusicAlbum.save_album(album.id, browse_id, build_api_album(title: '通常アルバム'))
    end

    assert_equal '通常アルバム', result.name
  end

  test 'update_album does not overwrite the payload when the album is degraded' do
    album = Album.create!(jan_code: "ytmusic-album-degraded-update-#{SecureRandom.hex(4)}")
    browse_id = "MPREb_#{SecureRandom.hex(4)}"
    ytmusic_album = YtmusicAlbum.save_album(album.id, browse_id, build_api_album(title: '既存アルバム'))
    original_payload = ytmusic_album.reload.payload

    result = ytmusic_album.update_album(
      build_api_album(title: '劣化アルバム', degraded: true),
      "https://music.youtube.com/browse/#{browse_id}"
    )

    assert_not result
    assert_equal original_payload, ytmusic_album.reload.payload
    assert_equal '既存アルバム', ytmusic_album.name
  end

  test 'update_album updates as usual when the album is not degraded' do
    album = Album.create!(jan_code: "ytmusic-album-normal-update-#{SecureRandom.hex(4)}")
    browse_id = "MPREb_#{SecureRandom.hex(4)}"
    ytmusic_album = YtmusicAlbum.save_album(album.id, browse_id, build_api_album(title: '更新前アルバム'))

    result = ytmusic_album.update_album(
      build_api_album(title: '更新後アルバム'),
      "https://music.youtube.com/browse/#{browse_id}"
    )

    assert result
    assert_equal '更新後アルバム', ytmusic_album.reload.name
  end

  test 'update_album rejects a fetch result with fewer playable tracks than the existing payload (regression guard)' do
    album = Album.create!(jan_code: "ytmusic-album-regression-decrease-#{SecureRandom.hex(4)}")
    browse_id = "MPREb_#{SecureRandom.hex(4)}"
    ytmusic_album = YtmusicAlbum.create!(album:, browse_id:, name: '既存アルバム', payload: playable_tracks_payload(10))

    result = ytmusic_album.update_album(
      build_api_album(title: '悪化アルバム', playable_track_count: 8),
      "https://music.youtube.com/browse/#{browse_id}"
    )

    assert_not result
    assert_equal '既存アルバム', ytmusic_album.reload.name
    assert_equal playable_tracks_payload(10), ytmusic_album.payload
  end

  test 'update_album updates when the playable track count stays the same (regression guard allows equal)' do
    album = Album.create!(jan_code: "ytmusic-album-regression-same-#{SecureRandom.hex(4)}")
    browse_id = "MPREb_#{SecureRandom.hex(4)}"
    ytmusic_album = YtmusicAlbum.create!(album:, browse_id:, name: '既存アルバム', payload: playable_tracks_payload(10))

    result = ytmusic_album.update_album(
      build_api_album(title: '更新後アルバム', playable_track_count: 10),
      "https://music.youtube.com/browse/#{browse_id}"
    )

    assert result
    assert_equal '更新後アルバム', ytmusic_album.reload.name
  end

  test 'update_album updates when the playable track count increases (regression guard allows improvement)' do
    album = Album.create!(jan_code: "ytmusic-album-regression-increase-#{SecureRandom.hex(4)}")
    browse_id = "MPREb_#{SecureRandom.hex(4)}"
    ytmusic_album = YtmusicAlbum.create!(album:, browse_id:, name: '既存アルバム', payload: playable_tracks_payload(10))

    result = ytmusic_album.update_album(
      build_api_album(title: '更新後アルバム', playable_track_count: 12),
      "https://music.youtube.com/browse/#{browse_id}"
    )

    assert result
    assert_equal '更新後アルバム', ytmusic_album.reload.name
  end

  test 'update_album updates even with few playable tracks when the existing payload has no tracks (regression guard does not apply)' do
    album = Album.create!(jan_code: "ytmusic-album-regression-empty-#{SecureRandom.hex(4)}")
    browse_id = "MPREb_#{SecureRandom.hex(4)}"
    ytmusic_album = YtmusicAlbum.create!(album:, browse_id:, name: '既存アルバム', payload: {})

    result = ytmusic_album.update_album(
      build_api_album(title: '更新後アルバム', playable_track_count: 1),
      "https://music.youtube.com/browse/#{browse_id}"
    )

    assert result
    assert_equal '更新後アルバム', ytmusic_album.reload.name
  end

  test 'reports progress while fetching YouTube Music albums' do
    album = Album.create!(jan_code: "ytmusic-progress-#{SecureRandom.hex(4)}")
    updates = []
    processed_albums = []

    with_ytmusic_album_processors(->(processed_album) { processed_albums << processed_album }) do
      with_ytmusic_album_url_updater do
        Album.unscoped.where(id: album.id).scoping do
          YtmusicAlbum.fetch_albums(progress_callback: ->(**attrs) { updates << attrs })
        end
      end
    end

    assert_equal [album], processed_albums
    assert_equal(
      { current: 0, total: 1, message: 'YouTube Musicアルバム候補を処理しています', reset: true },
      updates.first
    )
    assert_equal 1, updates.last.fetch(:current)
    assert_equal 1, updates.last.fetch(:total)
    assert_equal "YouTube Musicアルバム候補を処理しています: #{album.jan_code}", updates.last.fetch(:message)
  end

  private

  def playable_tracks_payload(count)
    { 'tracks' => Array.new(count) { |i| { 'video_id' => "v#{i}", 'track_number' => i + 1 } } }
  end

  def build_api_album(**attributes)
    YtmusicApiAlbum.new(
      title: 'YouTube Music Album',
      playlist_url: 'https://music.youtube.com/playlist?list=test',
      track_total_count: 10,
      year: '2026',
      degraded: false,
      playable_track_count: attributes[:degraded] ? 0 : 10,
      **attributes
    )
  end

  def with_ytmusic_album_processors(processor)
    singleton_class = YtmusicAlbum.singleton_class
    original_spotify_method = YtmusicAlbum.method(:process_album_with_spotify)
    original_apple_music_method = YtmusicAlbum.method(:process_album_with_apple_music)

    singleton_class.define_method(:process_album_with_spotify) { |album| processor.call(album) }
    singleton_class.define_method(:process_album_with_apple_music) { |_album| nil }
    yield
  ensure
    singleton_class.define_method(:process_album_with_spotify, original_spotify_method)
    singleton_class.define_method(:process_album_with_apple_music, original_apple_music_method)
  end

  def with_ytmusic_album_url_updater
    singleton_class = YtmusicAlbum.singleton_class
    original_method = YtmusicAlbum.method(:update_ytmusic_album_urls)

    singleton_class.define_method(:update_ytmusic_album_urls) { |**_kwargs| nil }
    yield
  ensure
    singleton_class.define_method(:update_ytmusic_album_urls, original_method)
  end
end
