# frozen_string_literal: true

require 'test_helper'

class YtmusicTrackTest < ActiveSupport::TestCase
  VIDEO_ID = 'video-bad-apple'
  PLAYLIST_ID = 'playlist-bad-apple'

  test 'save_track reuses the row with the same ytmusic_album_id and track_id when other attributes differ' do
    album, track, ytmusic_album = create_ytmusic_album
    payload_track = build_payload_track(title: 'Bad Apple!! feat. nomico')
    ytmusic_album.update!(payload: { 'tracks' => [payload_track] })

    assert_difference -> { YtmusicTrack.unscoped.count }, 1 do
      YtmusicTrack.save_track(album.id, track.id, ytmusic_album, payload_track)
    end

    renamed_track = build_payload_track(title: 'Bad Apple!! feat.nomico')
    ytmusic_album.update!(payload: { 'tracks' => [renamed_track] })

    assert_no_difference -> { YtmusicTrack.unscoped.count } do
      YtmusicTrack.save_track(album.id, track.id, ytmusic_album, renamed_track)
    end

    ytmusic_track = YtmusicTrack.unscoped.find_by!(ytmusic_album_id: ytmusic_album.id, track_id: track.id)

    assert_equal 'Bad Apple!! feat.nomico', ytmusic_track.name
  end

  test 'save_track skips a payload track whose url lacks the video id' do
    album, track, ytmusic_album = create_ytmusic_album
    payload_track = build_payload_track(url: 'https://music.youtube.com/watch?v=other')
    ytmusic_album.update!(payload: { 'tracks' => [payload_track] })

    assert_no_difference -> { YtmusicTrack.unscoped.count } do
      assert_nil YtmusicTrack.save_track(album.id, track.id, ytmusic_album, payload_track)
    end
  end

  test 'reports progress while fetching YouTube Music tracks' do
    album = Album.create!(jan_code: "ytmusic-track-progress-#{SecureRandom.hex(4)}")
    updates = []
    processed_albums = []

    with_ytmusic_track_processor(->(processed_album) { processed_albums << processed_album }) do
      Album.unscoped.where(id: album.id).scoping do
        YtmusicTrack.fetch_tracks(progress_callback: ->(**attrs) { updates << attrs })
      end
    end

    assert_equal [album], processed_albums
    assert_equal(
      { current: 0, total: 1, message: 'YouTube Musicトラックを取得しています', reset: true },
      updates.first
    )
    assert_equal 1, updates.last.fetch(:current)
    assert_equal 1, updates.last.fetch(:total)
    assert_equal "YouTube Musicトラックを処理しています: #{album.jan_code}", updates.last.fetch(:message)
  end

  private

  def create_ytmusic_album
    jan_code = "ytmusic-track-save-#{SecureRandom.hex(4)}"
    album = Album.create!(jan_code:)
    track = Track.create!(jan_code:, isrc: "ISRC#{SecureRandom.hex(4)}")
    ytmusic_album = YtmusicAlbum.create!(
      album:,
      browse_id: "MPREb_#{SecureRandom.hex(4)}",
      name: 'YouTube Music Album',
      total_tracks: 1,
      payload: {}
    )

    [album, track, ytmusic_album]
  end

  def build_payload_track(**attributes)
    {
      'title' => 'YouTube Music Track',
      'url' => "https://music.youtube.com/watch?v=#{VIDEO_ID}&list=#{PLAYLIST_ID}",
      'video_id' => VIDEO_ID,
      'playlist_id' => PLAYLIST_ID,
      'track_number' => 1
    }.merge(attributes.transform_keys(&:to_s))
  end

  def with_ytmusic_track_processor(processor)
    singleton_class = YtmusicTrack.singleton_class
    original_method = YtmusicTrack.method(:process_album)

    singleton_class.define_method(:process_album) { |album| processor.call(album) }
    yield
  ensure
    singleton_class.define_method(:process_album, original_method)
  end
end
