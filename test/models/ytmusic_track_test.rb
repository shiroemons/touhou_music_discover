# frozen_string_literal: true

require 'test_helper'

class YtmusicTrackTest < ActiveSupport::TestCase
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

  def with_ytmusic_track_processor(processor)
    singleton_class = YtmusicTrack.singleton_class
    original_method = YtmusicTrack.method(:process_album)

    singleton_class.define_method(:process_album) { |album| processor.call(album) }
    yield
  ensure
    singleton_class.define_method(:process_album, original_method)
  end
end
