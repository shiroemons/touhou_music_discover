# frozen_string_literal: true

require 'test_helper'

class SpotifyAlbumTest < ActiveSupport::TestCase
  test 'active album is unique per album' do
    album = Album.create!(jan_code: "spotify-active-#{SecureRandom.hex(4)}")
    create_spotify_album(album:, spotify_id: 'spotify-active-old', active: true)
    create_spotify_album(album:, spotify_id: 'spotify-active-inactive', active: false)

    duplicate = build_spotify_album(album:, spotify_id: 'spotify-active-new', active: true)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:album_id], 'has already been taken'
  end

  test 'album spotify_album returns active spotify album' do
    album = Album.create!(jan_code: "spotify-association-#{SecureRandom.hex(4)}")
    create_spotify_album(album:, spotify_id: 'spotify-association-inactive', active: false)
    active_album = create_spotify_album(album:, spotify_id: 'spotify-association-active', active: true)

    assert_equal active_album, album.reload.spotify_album
    assert_equal 2, album.spotify_albums.count
  end

  private

  def build_spotify_album(album:, spotify_id:, active:)
    SpotifyAlbum.new(
      album:,
      spotify_id:,
      album_type: 'album',
      name: spotify_id,
      label: Album::TOUHOU_MUSIC_LABEL,
      active:,
      payload: { 'available_markets' => ['JP'] }
    )
  end

  def create_spotify_album(...)
    build_spotify_album(...).tap(&:save!)
  end
end
