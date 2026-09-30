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

  test 'discovers unregistered artist IDs from saved albums without refetching known artists' do
    known_id = "known-#{SecureRandom.hex(4)}"
    new_id = "new-#{SecureRandom.hex(4)}"
    AppleMusicArtist.save_artist(build_api_artist(id: known_id, name: 'Known Artist'))
    2.times do |index|
      AppleMusicAlbum.create!(
        apple_music_id: "discovery-#{new_id}-#{index}",
        name: 'New Release',
        label: Album::TOUHOU_MUSIC_LABEL,
        payload: { 'relationships' => { 'artists' => { 'data' => [
          { 'id' => known_id }, { 'id' => new_id }, { 'id' => nil }
        ] } } }
      )
    end
    AppleMusicAlbum.create!(apple_music_id: "no-payload-#{new_id}", name: 'No Payload', label: Album::TOUHOU_MUSIC_LABEL)
    requested_ids = []
    new_artist = build_api_artist(id: new_id, name: 'New Artist')
    artist_api = Class.new do
      define_singleton_method(:get_collection_by_ids) do |ids|
        requested_ids << ids
        [new_artist]
      end
    end

    stub_const(AppleMusic, :Artist, artist_api) do
      assert_difference -> { AppleMusicArtist.count }, 1 do
        AppleMusicClient::Artist.fetch_from_albums
      end
      AppleMusicClient::Artist.fetch_from_albums
    end

    assert_equal [[new_id]], requested_ids
    assert_equal 'New Artist', AppleMusicArtist.find_by!(apple_music_id: new_id).name
  end

  private

  def build_api_artist(**attributes)
    AppleMusicApiArtist.new(url: 'https://music.apple.com/jp/artist/test', **attributes)
  end
end
