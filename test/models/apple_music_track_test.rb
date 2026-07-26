# frozen_string_literal: true

require 'test_helper'

class AppleMusicTrackTest < ActiveSupport::TestCase
  AppleMusicApiTrack = Struct.new(
    :id,
    :isrc,
    :name,
    :artist_name,
    :composer_name,
    :url,
    :release_date,
    :disc_number,
    :track_number,
    :duration_in_millis,
    keyword_init: true
  ) do
    def as_json(*)
      { 'id' => id, 'name' => name }
    end
  end

  # 同じトラックでも Apple Music 側で括弧が全角/半角に揺れることがあり、
  # 以前は表記が変わるたびに新しい行が作られていた。
  test 'save_track reuses the row when only the title notation changes' do
    apple_music_album = create_apple_music_album
    apple_music_id = "am-track-#{SecureRandom.hex(4)}"
    isrc = "ISRC#{SecureRandom.hex(4)}"

    assert_difference -> { AppleMusicTrack.unscoped.count }, 1 do
      AppleMusicTrack.save_track(
        apple_music_album,
        build_api_track(id: apple_music_id, isrc:, name: 'silently arity（SA ver.）')
      )
    end

    assert_no_difference -> { AppleMusicTrack.unscoped.count } do
      @apple_music_track = AppleMusicTrack.save_track(
        apple_music_album,
        build_api_track(id: apple_music_id, isrc:, name: 'silently arity(SA ver.)', duration_in_millis: 254_000)
      )
    end

    assert_equal 'silently arity(SA ver.)', @apple_music_track.reload.name
    assert_equal 254_000, @apple_music_track.duration_ms
  end

  test 'save_track creates separate rows for different Apple Music tracks in the same album' do
    apple_music_album = create_apple_music_album

    assert_difference -> { AppleMusicTrack.unscoped.count }, 2 do
      AppleMusicTrack.save_track(
        apple_music_album,
        build_api_track(id: "am-track-#{SecureRandom.hex(4)}", isrc: "ISRC#{SecureRandom.hex(4)}", track_number: 1)
      )
      AppleMusicTrack.save_track(
        apple_music_album,
        build_api_track(id: "am-track-#{SecureRandom.hex(4)}", isrc: "ISRC#{SecureRandom.hex(4)}", track_number: 2)
      )
    end
  end

  private

  def create_apple_music_album
    album = Album.create!(jan_code: "apple-music-track-#{SecureRandom.hex(4)}")

    AppleMusicAlbum.create!(
      album:,
      apple_music_id: "am-album-#{SecureRandom.hex(4)}",
      name: 'Apple Music Album',
      label: ::Album::TOUHOU_MUSIC_LABEL,
      payload: {}
    )
  end

  def build_api_track(**attributes)
    AppleMusicApiTrack.new(
      name: 'Apple Music Track',
      artist_name: '幽閉サテライト',
      composer_name: 'HiZuMi',
      url: 'https://music.apple.com/jp/song/test',
      release_date: Date.new(2026, 1, 1),
      disc_number: 1,
      track_number: 1,
      duration_in_millis: 240_000,
      **attributes
    )
  end
end
