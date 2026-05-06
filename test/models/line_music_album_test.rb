# frozen_string_literal: true

require 'test_helper'

class LineMusicAlbumTest < ActiveSupport::TestCase
  LineMusicApiAlbum = Struct.new(:album_id, :album_title, :release_date, :track_total_count, keyword_init: true) do
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

  private

  def build_line_music_api_album(...)
    LineMusicApiAlbum.new(...)
  end
end
