# frozen_string_literal: true

require 'test_helper'

class YtmusicTrackTest < ActiveSupport::TestCase
  VIDEO_ID = 'video-bad-apple'
  PLAYLIST_ID = 'playlist-bad-apple'

  # YtMusic::Video相当のFake。本リポジトリはwebmock/vcrを使わないため、
  # HTTPを伴う実クラスの代わりにこのFakeでモデル層の保存処理だけを検証する。
  FakeVideo = Struct.new(:publish_date, :upload_date, :release_date, :provided_by, keyword_init: true) do
    def art_track?
      provided_by.present?
    end

    def metadata
      { 'provided_by' => provided_by, 'publish_date' => publish_date&.iso8601 }
    end
  end

  test 'update_video_metadata: YtMusic::Videoの値を全カラムへ保存する' do
    album, track, ytmusic_album = create_ytmusic_album
    ytmusic_track = YtmusicTrack.create!(
      album:, ytmusic_album:, track:, name: 'Track', video_id: VIDEO_ID, playlist_id: PLAYLIST_ID
    )
    video = FakeVideo.new(
      publish_date: Date.new(2026, 6, 29),
      upload_date: Date.new(2026, 6, 28),
      release_date: Date.new(2026, 5, 4),
      provided_by: 'Rightsscale'
    )

    freeze_time do
      ytmusic_track.update_video_metadata(video)
      ytmusic_track.reload

      assert_equal Date.new(2026, 6, 29), ytmusic_track.published_on
      assert_equal Date.new(2026, 6, 28), ytmusic_track.uploaded_on
      assert_equal Date.new(2026, 5, 4), ytmusic_track.original_released_on
      assert_equal 'Rightsscale', ytmusic_track.provided_by
      assert ytmusic_track.art_track
      assert_equal video.metadata, ytmusic_track.video_metadata
      assert_equal Time.current, ytmusic_track.video_fetched_at
    end
  end

  test 'update_video_metadata: provided_byが取得できない場合はart_trackがfalseのまま保存される' do
    album, track, ytmusic_album = create_ytmusic_album
    ytmusic_track = YtmusicTrack.create!(
      album:, ytmusic_album:, track:, name: 'Track', video_id: VIDEO_ID, playlist_id: PLAYLIST_ID
    )
    video = FakeVideo.new(publish_date: Date.new(2026, 6, 29), upload_date: nil, release_date: nil, provided_by: nil)

    ytmusic_track.update_video_metadata(video)

    assert_not ytmusic_track.reload.art_track
    assert_nil ytmusic_track.provided_by
  end

  test 'video_metadata_missingスコープはvideo_fetched_atがnilの行だけを返す' do
    album, track, ytmusic_album = create_ytmusic_album
    fetched = YtmusicTrack.create!(
      album:, ytmusic_album:, track:, name: 'Track', video_id: VIDEO_ID, playlist_id: PLAYLIST_ID,
      video_fetched_at: Time.current
    )
    other_track = Track.create!(jan_code: album.jan_code, isrc: "ISRC#{SecureRandom.hex(4)}")
    not_fetched = YtmusicTrack.create!(
      album:, ytmusic_album:, track: other_track, name: 'Track',
      video_id: "#{VIDEO_ID}-2", playlist_id: "#{PLAYLIST_ID}-2"
    )

    missing_ids = YtmusicTrack.unscoped.video_metadata_missing.pluck(:id)

    assert_includes missing_ids, not_fetched.id
    assert_not_includes missing_ids, fetched.id
  end

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
