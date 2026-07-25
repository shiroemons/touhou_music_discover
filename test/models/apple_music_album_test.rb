# frozen_string_literal: true

require 'test_helper'

class AppleMusicAlbumTest < ActiveSupport::TestCase
  AppleMusicApiAlbum = Struct.new(
    :id,
    :name,
    :record_label,
    :url,
    :release_date,
    :track_count,
    :upc,
    keyword_init: true
  ) do
    def as_json(*)
      { 'id' => id, 'name' => name }
    end
  end

  test 'save_album reuses the row with the same apple_music_id when other attributes differ' do
    jan_code = "apple-music-album-#{SecureRandom.hex(4)}"
    apple_music_id = "am-album-#{SecureRandom.hex(4)}"

    assert_difference -> { AppleMusicAlbum.unscoped.count }, 1 do
      AppleMusicAlbum.save_album(build_api_album(id: apple_music_id, upc: jan_code, name: '幻想郷スタイル'))
    end

    assert_no_difference -> { AppleMusicAlbum.unscoped.count } do
      @apple_music_album = AppleMusicAlbum.save_album(
        build_api_album(
          id: apple_music_id,
          upc: jan_code,
          name: '幻想郷スタイル (Remastered)',
          track_count: 12
        )
      )
    end

    assert_equal '幻想郷スタイル (Remastered)', @apple_music_album.reload.name
    assert_equal 12, @apple_music_album.total_tracks
  end

  test 'save_album skips albums that are not distributed by the Touhou music label' do
    api_album = build_api_album(
      id: "am-album-#{SecureRandom.hex(4)}",
      upc: "apple-music-album-other-label-#{SecureRandom.hex(4)}",
      record_label: 'Other Label'
    )

    assert_no_difference -> { AppleMusicAlbum.unscoped.count } do
      assert_nil AppleMusicAlbum.save_album(api_album)
    end
  end

  private

  def build_api_album(**attributes)
    AppleMusicApiAlbum.new(
      name: 'Apple Music Album',
      record_label: ::Album::TOUHOU_MUSIC_LABEL,
      url: 'https://music.apple.com/jp/album/test',
      release_date: Date.new(2026, 1, 1),
      track_count: 10,
      **attributes
    )
  end
end
