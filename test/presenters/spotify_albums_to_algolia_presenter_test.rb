# frozen_string_literal: true

require 'test_helper'

class SpotifyAlbumsToAlgoliaPresenterTest < ActiveSupport::TestCase
  test 'exports tracks from active spotify album only' do
    album = Album.create!(jan_code: "presenter-active-spotify-#{SecureRandom.hex(4)}", is_touhou: true)
    track = Track.create!(album:, isrc: "JPABC#{SecureRandom.alphanumeric(7).upcase}")
    inactive_spotify_album = create_spotify_album(album:, spotify_id: 'presenter-inactive-spotify-album', active: false)
    active_spotify_album = create_spotify_album(album:, spotify_id: 'presenter-active-spotify-album', active: true)
    create_spotify_track(album:, track:, spotify_album: inactive_spotify_album, spotify_id: 'presenter-inactive-spotify-track')
    create_spotify_track(album:, track:, spotify_album: active_spotify_album, spotify_id: 'presenter-active-spotify-track')

    json = SpotifyAlbumsToAlgoliaPresenter.new([album.reload]).as_json

    assert_equal 1, json.size
    assert_equal(['presenter-active-spotify-track'], json.first.fetch(:tracks).map { it.fetch(:name) })
  end

  private

  def create_spotify_album(album:, spotify_id:, active:)
    SpotifyAlbum.create!(
      album:,
      spotify_id:,
      album_type: 'album',
      name: spotify_id,
      label: Album::TOUHOU_MUSIC_LABEL,
      release_date: Date.new(2026, 5, 6),
      total_tracks: 1,
      active:,
      payload: {
        'artists' => [],
        'copyrights' => [],
        'images' => [],
        'available_markets' => ['JP']
      }
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
