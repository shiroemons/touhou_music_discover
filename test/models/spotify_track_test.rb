# frozen_string_literal: true

require 'test_helper'

class SpotifyTrackTest < ActiveSupport::TestCase
  SpotifyApiTrack = Struct.new(
    :id,
    :name,
    :external_ids,
    :external_urls,
    :disc_number,
    :track_number,
    :duration_ms,
    keyword_init: true
  ) do
    def as_json(*)
      { 'id' => id, 'name' => name, 'artists' => [] }
    end
  end

  test 'save_track reuses the row with the same spotify_album_id and spotify_id when other attributes differ' do
    spotify_album = create_spotify_album
    spotify_id = "spotify-track-#{SecureRandom.hex(4)}"
    isrc = "ISRC#{SecureRandom.hex(4)}"

    assert_difference -> { SpotifyTrack.unscoped.count }, 1 do
      SpotifyTrack.save_track(spotify_album, build_api_track(id: spotify_id, isrc:, name: '色は匂へど 散りぬるを'))
    end

    assert_no_difference -> { SpotifyTrack.unscoped.count } do
      @spotify_track = SpotifyTrack.save_track(
        spotify_album,
        build_api_track(id: spotify_id, isrc:, name: '色は匂へど散りぬるを', track_number: 3)
      )
    end

    assert_equal '色は匂へど散りぬるを', @spotify_track.reload.name
    assert_equal 3, @spotify_track.track_number
  end

  test 'save_track returns nil for blank arguments' do
    spotify_album = create_spotify_album

    assert_no_difference -> { SpotifyTrack.unscoped.count } do
      assert_nil SpotifyTrack.save_track(nil, build_api_track(id: 'x', isrc: 'y'))
      assert_nil SpotifyTrack.save_track(spotify_album, nil)
    end
  end

  private

  def create_spotify_album
    album = Album.create!(jan_code: "spotify-track-#{SecureRandom.hex(4)}")

    SpotifyAlbum.create!(
      album:,
      spotify_id: "spotify-album-#{SecureRandom.hex(4)}",
      album_type: 'album',
      name: 'Spotify Album',
      label: ::Album::TOUHOU_MUSIC_LABEL,
      release_date: Date.new(2026, 1, 1),
      payload: {}
    )
  end

  def build_api_track(isrc:, **attributes)
    SpotifyApiTrack.new(
      name: 'Spotify Track',
      external_ids: { 'isrc' => isrc },
      external_urls: { 'spotify' => 'https://open.spotify.com/track/test' },
      disc_number: 1,
      track_number: 1,
      duration_ms: 240_000,
      **attributes
    )
  end
end
