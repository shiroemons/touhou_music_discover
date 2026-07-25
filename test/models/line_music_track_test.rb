# frozen_string_literal: true

require 'test_helper'

class LineMusicTrackTest < ActiveSupport::TestCase
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

  def with_line_music_track_processor(processor)
    singleton_class = LineMusicTrack.singleton_class
    original_method = LineMusicTrack.method(:process_album)

    singleton_class.define_method(:process_album) { |album| processor.call(album) }
    yield
  ensure
    singleton_class.define_method(:process_album, original_method)
  end
end
