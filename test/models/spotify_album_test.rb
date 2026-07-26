# frozen_string_literal: true

require 'test_helper'

class SpotifyAlbumTest < ActiveSupport::TestCase
  # save_album に渡す SpotifyApi::Response / RSpotify::Album のダブル。
  # available_markets が nil のときは as_json からキーごと落とし、Spotify がフィールド自体を
  # 返さなくなった縮退レスポンスを再現する。
  SpotifyApiAlbumDouble = Struct.new(
    :id,
    :album_type,
    :name,
    :label,
    :external_ids,
    :external_urls,
    :total_tracks,
    :release_date,
    :available_markets,
    keyword_init: true
  ) do
    def as_json(*)
      body = {
        'id' => id,
        'album_type' => album_type,
        'name' => name,
        'label' => label,
        'external_ids' => external_ids,
        'external_urls' => external_urls,
        'total_tracks' => total_tracks,
        'release_date' => release_date,
        'artists' => []
      }
      return body if available_markets.nil?

      body.merge('available_markets' => available_markets)
    end
  end

  test 'active album is unique per album' do
    album = Album.create!(jan_code: "spotify-active-#{SecureRandom.hex(4)}")
    create_spotify_album(album:, spotify_id: 'spotify-active-old', active: true)
    create_spotify_album(album:, spotify_id: 'spotify-active-inactive', active: false)

    duplicate = build_spotify_album(album:, spotify_id: 'spotify-active-new', active: true)

    assert_not duplicate.valid?
    assert(duplicate.errors.details[:album_id].any? { |error| error[:error] == :taken })
  end

  test 'album spotify_album returns active spotify album' do
    album = Album.create!(jan_code: "spotify-association-#{SecureRandom.hex(4)}")
    create_spotify_album(album:, spotify_id: 'spotify-association-inactive', active: false)
    active_album = create_spotify_album(album:, spotify_id: 'spotify-association-active', active: true)

    assert_equal active_album, album.reload.spotify_album
    assert_equal 2, album.spotify_albums.count
  end

  test 'payload_preserving_available_markets keeps the existing markets when the new list is empty' do
    spotify_album = create_spotify_album_with_payload(
      'spotify-markets-empty',
      { 'available_markets' => %w[JP US], 'name' => 'Old Name' }
    )

    merged = spotify_album.payload_preserving_available_markets({ 'available_markets' => [], 'name' => 'New Name' })

    assert_equal %w[JP US], merged['available_markets']
    assert_equal 'New Name', merged['name']
  end

  test 'payload_preserving_available_markets keeps the existing markets when the new payload has no key' do
    spotify_album = create_spotify_album_with_payload(
      'spotify-markets-missing',
      { 'available_markets' => %w[JP US], 'name' => 'Old Name' }
    )

    merged = spotify_album.payload_preserving_available_markets({ 'name' => 'New Name' })

    assert_equal %w[JP US], merged['available_markets']
    assert_equal 'New Name', merged['name']
  end

  # 配信国が本当に減ったケースは反映されるべきなので、非空の新しい値は件数が減っていても採用する。
  test 'payload_preserving_available_markets uses the new markets even when there are fewer of them' do
    spotify_album = create_spotify_album_with_payload(
      'spotify-markets-fewer',
      { 'available_markets' => %w[JP US GB] }
    )

    merged = spotify_album.payload_preserving_available_markets({ 'available_markets' => ['JP'] })

    assert_equal ['JP'], merged['available_markets']
  end

  test 'payload_preserving_available_markets returns the new payload as is when there is nothing to preserve' do
    album = Album.create!(jan_code: "spotify-markets-new-#{SecureRandom.hex(4)}")
    spotify_album = build_spotify_album(album:, spotify_id: 'spotify-markets-new', active: true, payload: nil)
    new_payload = { 'available_markets' => [], 'name' => 'New Name' }

    assert_equal new_payload, spotify_album.payload_preserving_available_markets(new_payload)
    assert_empty spotify_album.payload_preserving_available_markets(nil)
  end

  # #559 で防ぎたい本体の不具合: 縮退レスポンスで jp_available? が true → false に反転すると、
  # preferred_active_album が重複アルバムの選択を誤る。
  test 'jp_available? stays true after a degraded payload is applied' do
    spotify_album = create_spotify_album_with_payload(
      'spotify-markets-jp',
      { 'available_markets' => %w[JP US] }
    )

    spotify_album.update!(payload: spotify_album.payload_preserving_available_markets({ 'available_markets' => [] }))

    assert_equal %w[JP US], spotify_album.reload.payload['available_markets']
    assert_predicate spotify_album, :jp_available?
  end

  test 'save_album preserves available_markets when Spotify returns a degraded album' do
    jan_code = "spotify-save-album-#{SecureRandom.hex(4)}"
    SpotifyAlbum.save_album(spotify_api_album_double(jan_code:, available_markets: %w[JP US]))

    spotify_album = SpotifyAlbum.save_album(spotify_api_album_double(jan_code:, name: 'Renamed Album', available_markets: []))

    assert_equal %w[JP US], spotify_album.reload.payload['available_markets']
    assert_equal 'Renamed Album', spotify_album.payload['name']
    assert_predicate spotify_album, :jp_available?
  end

  private

  def build_spotify_album(album:, spotify_id:, active:, payload: { 'available_markets' => ['JP'] })
    SpotifyAlbum.new(
      album:,
      spotify_id:,
      album_type: 'album',
      name: spotify_id,
      label: Album::TOUHOU_MUSIC_LABEL,
      active:,
      payload:
    )
  end

  def create_spotify_album(...)
    build_spotify_album(...).tap(&:save!)
  end

  def create_spotify_album_with_payload(spotify_id, payload)
    album = Album.create!(jan_code: "#{spotify_id}-#{SecureRandom.hex(4)}")
    create_spotify_album(album:, spotify_id:, active: true, payload:)
  end

  def spotify_api_album_double(jan_code:, available_markets:, name: 'Spotify Album')
    SpotifyApiAlbumDouble.new(
      id: "spotify-#{jan_code}",
      album_type: 'album',
      name:,
      label: Album::TOUHOU_MUSIC_LABEL,
      external_ids: { 'upc' => jan_code },
      external_urls: { 'spotify' => 'https://open.spotify.com/album/test' },
      total_tracks: 0,
      release_date: '2026-01-01',
      available_markets:
    )
  end
end
