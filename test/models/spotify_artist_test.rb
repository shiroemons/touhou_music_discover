# frozen_string_literal: true

require 'test_helper'

class SpotifyArtistTest < ActiveSupport::TestCase
  SpotifyApiArtist = Struct.new(:id, :name, :external_urls, :followers, keyword_init: true) do
    def as_json(*)
      { 'id' => id, 'name' => name }
    end
  end

  test 'save_artist reuses the row with the same spotify_id when other attributes differ' do
    spotify_id = "spotify-artist-#{SecureRandom.hex(4)}"

    assert_difference -> { SpotifyArtist.unscoped.count }, 1 do
      SpotifyArtist.save_artist(build_api_artist(id: spotify_id, name: 'ZYTOKINE', follower_count: 100))
    end

    assert_no_difference -> { SpotifyArtist.unscoped.count } do
      @spotify_artist = SpotifyArtist.save_artist(
        build_api_artist(id: spotify_id, name: 'ZYTOKINE / 隣人', follower_count: 250)
      )
    end

    assert_equal 'ZYTOKINE / 隣人', @spotify_artist.reload.name
    assert_equal 250, @spotify_artist.follower_count
  end

  test 'save_artist returns nil for a blank artist' do
    assert_no_difference -> { SpotifyArtist.unscoped.count } do
      assert_nil SpotifyArtist.save_artist(nil)
    end
  end

  private

  def build_api_artist(follower_count:, **attributes)
    SpotifyApiArtist.new(
      external_urls: { 'spotify' => 'https://open.spotify.com/artist/test' },
      followers: { 'total' => follower_count },
      **attributes
    )
  end
end
