# frozen_string_literal: true

require 'test_helper'

module SpotifyClient
  class AlbumTest < ActiveSupport::TestCase
    SpotifyApiAlbum = Struct.new(
      :id,
      :album_type,
      :name,
      :label,
      :external_ids,
      :external_urls,
      :total_tracks,
      :release_date,
      keyword_init: true
    ) do
      def tracks
        []
      end

      def as_json(*)
        {
          'id' => id,
          'album_type' => album_type,
          'name' => name,
          'label' => label,
          'external_ids' => external_ids,
          'external_urls' => external_urls,
          'total_tracks' => total_tracks,
          'release_date' => release_date,
          'artists' => [],
          'available_markets' => ['JP']
        }
      end
    end

    test 'creates Spotify album by Apple Music JAN' do
      jan_code = "spotify-jan-search-#{SecureRandom.hex(4)}"
      album = create_album_with_apple_music(jan_code:)
      api_album = spotify_api_album(jan_code:)
      queries = []

      spotify_album_client = Class.new do
        define_singleton_method(:search) do |query, **_options|
          queries << query
          [api_album]
        end
      end

      target_scope = ::Album.where(id: album.id).includes(:apple_music_album)
      with_missing_spotify_album_scope(target_scope) do
        stub_const(RSpotify, :Album, spotify_album_client) do
          assert_difference -> { SpotifyAlbum.unscoped.count }, 1 do
            @result = SpotifyClient::Album.fetch_missing_albums_by_apple_music_jan(sleep_interval: 0)
          end
        end
      end

      spotify_album = SpotifyAlbum.unscoped.find_by!(album:)
      assert_equal "spotify-#{jan_code}", spotify_album.spotify_id
      assert_equal 'Spotify JAN Album', spotify_album.name
      assert_equal "upc:#{jan_code}", queries.last
      assert_equal 1, @result[:created]
      assert_equal 0, @result[:errors]
    end

    test 'does not search albums that already have inactive Spotify albums' do
      jan_code = "spotify-jan-skip-#{SecureRandom.hex(4)}"
      album = create_album_with_apple_music(jan_code:)
      SpotifyAlbum.create!(
        album:,
        spotify_id: "inactive-#{jan_code}",
        album_type: 'album',
        name: 'Inactive Spotify Album',
        label: ::Album::TOUHOU_MUSIC_LABEL,
        active: false,
        payload: { 'available_markets' => ['JP'] }
      )

      scope = SpotifyClient::Album.send(:missing_spotify_albums_with_apple_music)

      assert_empty scope.where(id: album.id)
    end

    private

    def create_album_with_apple_music(jan_code:)
      ::Album.create!(jan_code:).tap do |album|
        AppleMusicAlbum.create!(
          album:,
          apple_music_id: "apple-#{jan_code}",
          name: 'Apple Music Album',
          label: ::Album::TOUHOU_MUSIC_LABEL,
          url: 'https://music.apple.com/test',
          release_date: Date.new(2026, 1, 1),
          total_tracks: 0,
          payload: {}
        )
      end
    end

    def spotify_api_album(jan_code:)
      SpotifyApiAlbum.new(
        id: "spotify-#{jan_code}",
        album_type: 'album',
        name: 'Spotify JAN Album',
        label: ::Album::TOUHOU_MUSIC_LABEL,
        external_ids: { 'upc' => jan_code },
        external_urls: { 'spotify' => 'https://open.spotify.com/album/test' },
        total_tracks: 0,
        release_date: '2026-01-01'
      )
    end

    def with_missing_spotify_album_scope(scope)
      singleton_class = SpotifyClient::Album.singleton_class
      original_method = SpotifyClient::Album.method(:missing_spotify_albums_with_apple_music)

      singleton_class.define_method(:missing_spotify_albums_with_apple_music) { scope }
      singleton_class.send(:private, :missing_spotify_albums_with_apple_music)
      yield
    ensure
      singleton_class.define_method(:missing_spotify_albums_with_apple_music, original_method)
      singleton_class.send(:private, :missing_spotify_albums_with_apple_music)
    end
  end
end
