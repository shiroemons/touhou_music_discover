# frozen_string_literal: true

require 'test_helper'

class TrackTest < ActiveSupport::TestCase
  test 'spotify_track returns track from active spotify album' do
    album = Album.create!(jan_code: "track-active-spotify-#{SecureRandom.hex(4)}")
    track = Track.create!(album:, isrc: "JPABC#{SecureRandom.alphanumeric(7).upcase}")
    inactive_spotify_album = create_spotify_album(album:, spotify_id: 'track-inactive-spotify-album', active: false)
    active_spotify_album = create_spotify_album(album:, spotify_id: 'track-active-spotify-album', active: true)
    inactive_spotify_track = create_spotify_track(album:, track:, spotify_album: inactive_spotify_album, spotify_id: 'track-inactive-spotify-track')
    active_spotify_track = create_spotify_track(album:, track:, spotify_album: active_spotify_album, spotify_id: 'track-active-spotify-track')

    assert_equal active_spotify_track, track.spotify_track(album)
    assert_not_equal inactive_spotify_track, track.spotify_track(album)
  end

  private

  def create_spotify_album(album:, spotify_id:, active:)
    SpotifyAlbum.create!(
      album:,
      spotify_id:,
      album_type: 'album',
      name: spotify_id,
      label: Album::TOUHOU_MUSIC_LABEL,
      active:,
      payload: { 'available_markets' => ['JP'] }
    )
  end

  def create_spotify_track(album:, track:, spotify_album:, spotify_id:)
    SpotifyTrack.create!(
      album:,
      track:,
      spotify_album:,
      spotify_id:,
      name: spotify_id,
      label: Album::TOUHOU_MUSIC_LABEL,
      disc_number: 1,
      track_number: 1,
      duration_ms: 180_000,
      payload: {}
    )
  end
end
