# frozen_string_literal: true

require 'test_helper'

class LineMusicTrackTest < ActiveSupport::TestCase
  test 'reports progress while fetching LINE MUSIC tracks' do
    album = Album.create!(jan_code: "line-music-track-progress-#{SecureRandom.hex(4)}")
    updates = []
    processed_albums = []

    with_line_music_track_processor(->(processed_album) { processed_albums << processed_album }) do
      with_parallel_each_running_inline do
        Album.unscoped.where(id: album.id).scoping do
          LineMusicTrack.fetch_tracks(progress_callback: ->(**attrs) { updates << attrs })
        end
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

  def with_line_music_track_processor(processor)
    singleton_class = LineMusicTrack.singleton_class
    original_method = LineMusicTrack.method(:process_album)

    singleton_class.define_method(:process_album) { |album| processor.call(album) }
    yield
  ensure
    singleton_class.define_method(:process_album, original_method)
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
