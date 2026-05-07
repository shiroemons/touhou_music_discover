# frozen_string_literal: true

require 'test_helper'

class YtmusicAlbumTest < ActiveSupport::TestCase
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

  def with_ytmusic_album_processors(processor)
    singleton_class = YtmusicAlbum.singleton_class
    original_spotify_method = YtmusicAlbum.method(:process_album_with_spotify)
    original_apple_music_method = YtmusicAlbum.method(:process_album_with_apple_music)

    singleton_class.define_method(:process_album_with_spotify) { |album| processor.call(album) }
    singleton_class.define_method(:process_album_with_apple_music) { |_album| }
    yield
  ensure
    singleton_class.define_method(:process_album_with_spotify, original_spotify_method)
    singleton_class.define_method(:process_album_with_apple_music, original_apple_music_method)
  end

  def with_ytmusic_album_url_updater
    singleton_class = YtmusicAlbum.singleton_class
    original_method = YtmusicAlbum.method(:update_ytmusic_album_urls)

    singleton_class.define_method(:update_ytmusic_album_urls) { |progress_callback: nil| }
    yield
  ensure
    singleton_class.define_method(:update_ytmusic_album_urls, original_method)
  end
end
