# frozen_string_literal: true

require 'test_helper'

class AppleMusicArtistTest < ActiveSupport::TestCase
  AppleMusicApiArtist = Struct.new(:id, :name, :url, keyword_init: true) do
    def as_json(*)
      { 'id' => id, 'name' => name }
    end
  end

  test 'save_artist reuses the row with the same apple_music_id when other attributes differ' do
    apple_music_id = "am-artist-#{SecureRandom.hex(4)}"

    assert_difference -> { AppleMusicArtist.unscoped.count }, 1 do
      AppleMusicArtist.save_artist(build_api_artist(id: apple_music_id, name: '幽閉サテライト'))
    end

    assert_no_difference -> { AppleMusicArtist.unscoped.count } do
      AppleMusicArtist.save_artist(
        build_api_artist(
          id: apple_music_id,
          name: '幽閉サテライト (Yuuhei Satellite)',
          url: 'https://music.apple.com/jp/artist/renamed'
        )
      )
    end

    apple_music_artist = AppleMusicArtist.unscoped.find_by!(apple_music_id:)

    assert_equal '幽閉サテライト (Yuuhei Satellite)', apple_music_artist.name
    assert_equal 'https://music.apple.com/jp/artist/renamed', apple_music_artist.url
  end

  private

  def build_api_artist(**attributes)
    AppleMusicApiArtist.new(url: 'https://music.apple.com/jp/artist/test', **attributes)
  end
end
