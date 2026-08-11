# frozen_string_literal: true

require 'test_helper'

class AlbumTitleResolverTest < ActiveSupport::TestCase
  test 'selects one complete catalog with Japanese titles for the whole album' do
    album, tracks = create_album_with_tracks('resolver-japanese')
    spotify_album = create_spotify_album(album, 'resolver-spotify', 'English Collection', total_tracks: 2)
    apple_album = create_apple_music_album(album, 'resolver-apple', '日本語コレクション', total_tracks: 2)
    create_spotify_tracks(spotify_album, tracks, ['Moonlight', 'The World'])
    create_apple_music_tracks(apple_album, tracks, %w[月夜 世界])

    resolution = AlbumTitleResolver.for(album)

    assert_equal :apple_music, resolution.source
    assert_equal :ok, resolution.status
    assert_equal '日本語コレクション', resolution.display_album_name
    assert_equal '月夜', resolution.display_track_name(tracks.first)
    assert_equal [2, 2], resolution.coverage
  end

  test 'manual source override wins when that catalog is complete' do
    album, tracks = create_album_with_tracks('resolver-override')
    spotify_album = create_spotify_album(album, 'resolver-override-spotify', 'English Collection', total_tracks: 2)
    apple_album = create_apple_music_album(album, 'resolver-override-apple', '日本語コレクション', total_tracks: 2)
    create_spotify_tracks(spotify_album, tracks, ['Moonlight', 'The World'])
    create_apple_music_tracks(apple_album, tracks, %w[月夜 世界])
    album.update!(title_source_override: 'spotify')

    resolution = AlbumTitleResolver.for(album.reload)

    assert_equal :spotify, resolution.source
    assert_predicate resolution, :override?
    assert_equal 'Moonlight', resolution.display_track_name(tracks.first)

    album.update!(title_source_override: 'ytmusic')
    resolution = AlbumTitleResolver.for(album.reload)

    assert_equal :apple_music, resolution.source
    assert_predicate resolution, :invalid_override?
    assert_not resolution.override?
  end

  test 'ignores an incomplete preferred catalog instead of mixing services' do
    album, tracks = create_album_with_tracks('resolver-incomplete')
    spotify_album = create_spotify_album(album, 'resolver-incomplete-spotify', 'English Collection', total_tracks: 2)
    apple_album = create_apple_music_album(album, 'resolver-incomplete-apple', '日本語コレクション', total_tracks: 2)
    create_spotify_tracks(spotify_album, tracks, ['Moonlight', 'The World'])
    create_apple_music_tracks(apple_album, tracks.first(1), ['月夜'])

    resolution = AlbumTitleResolver.for(album)

    assert_equal :spotify, resolution.source
    assert_equal :ok, resolution.status
    assert_equal 'The World', resolution.display_track_name(tracks.second)
  end

  test 'bulk resolution is keyed by album id' do
    album, = create_album_with_tracks('resolver-bulk')
    create_spotify_album(album, 'resolver-bulk-spotify', 'English Collection', total_tracks: 0)

    resolutions = AlbumTitleResolver.for_many([album])

    assert_equal album.display_name, resolutions.fetch(album.id).display_album_name
  end

  private

  def create_album_with_tracks(prefix)
    album = Album.create!(jan_code: "#{prefix}-#{SecureRandom.hex(4)}")
    tracks = Array.new(2) do |index|
      Track.create!(album:, isrc: "JPRES#{SecureRandom.alphanumeric(7).upcase}#{index}")
    end
    [album, tracks]
  end

  def create_spotify_album(album, spotify_id, name, total_tracks:)
    SpotifyAlbum.create!(
      album:,
      spotify_id:,
      album_type: 'album',
      name:,
      label: Album::TOUHOU_MUSIC_LABEL,
      total_tracks:,
      active: true,
      payload: {}
    )
  end

  def create_apple_music_album(album, apple_music_id, name, total_tracks:)
    AppleMusicAlbum.create!(
      album:,
      apple_music_id:,
      name:,
      label: Album::TOUHOU_MUSIC_LABEL,
      total_tracks:,
      payload: {}
    )
  end

  def create_spotify_tracks(spotify_album, tracks, names)
    tracks.each_with_index do |track, index|
      SpotifyTrack.create!(
        album: spotify_album.album,
        track:,
        spotify_album:,
        spotify_id: "#{spotify_album.spotify_id}-track-#{index}",
        name: names.fetch(index),
        label: Album::TOUHOU_MUSIC_LABEL,
        disc_number: 1,
        track_number: index + 1,
        duration_ms: 180_000,
        payload: {}
      )
    end
  end

  def create_apple_music_tracks(apple_album, tracks, names)
    tracks.each_with_index do |track, index|
      AppleMusicTrack.create!(
        album: apple_album.album,
        track:,
        apple_music_album: apple_album,
        apple_music_id: "#{apple_album.apple_music_id}-track-#{index}",
        artist_name: '',
        composer_name: '',
        name: names.fetch(index),
        label: Album::TOUHOU_MUSIC_LABEL,
        disc_number: 1,
        track_number: index + 1,
        payload: {}
      )
    end
  end
end
