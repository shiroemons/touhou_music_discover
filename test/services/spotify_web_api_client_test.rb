# frozen_string_literal: true

require 'test_helper'

module SpotifyWebApi
  class ClientTest < ActiveSupport::TestCase
    class FakeSpotifyClient
      class << self
        attr_accessor :last_instance
      end

      attr_reader :calls, :config

      def initialize(config)
        @config = config
        @calls = []
        self.class.last_instance = self
      end

      def playlist(playlist_id)
        calls << [:playlist, playlist_id]
        { 'id' => playlist_id }
      end

      def tracks(track_ids)
        calls << [:tracks, track_ids]
        { 'tracks' => track_ids.map { |id| { 'id' => id } } }
      end

      def albums(album_ids)
        calls << [:albums, album_ids]
        { 'albums' => album_ids.map { |id| { 'id' => id } } }
      end

      def search(entity, term, options)
        calls << [:search, entity, term, options]
        { "#{entity}s" => { 'items' => [] } }
      end

      def request!(*args, **kwargs)
        calls << [:request, args, kwargs]
        { 'ok' => true }
      end
    end

    setup do
      FakeSpotifyClient.last_instance = nil
    end

    test 'configures spotify client with stable defaults' do
      Client.new(access_token: 'token', app_mode: :development, spotify_client_class: FakeSpotifyClient)

      assert_equal(
        {
          access_token: 'token',
          app_mode: :development,
          raise_errors: true,
          retries: 1,
          read_timeout: 10,
          write_timeout: 10,
          persistent: false
        },
        FakeSpotifyClient.last_instance.config
      )
    end

    test 'requires access token' do
      assert_raises(ArgumentError) do
        Client.new(access_token: '', spotify_client_class: FakeSpotifyClient)
      end
    end

    test 'wraps playlist operations with normalized track uris' do
      client = Client.new(access_token: 'token', spotify_client_class: FakeSpotifyClient)

      assert_equal({ 'id' => 'playlist-1' }, client.playlist('playlist-1'))
      client.playlist_items('playlist-1', limit: 50)
      client.create_playlist(name: 'Playlist', public: false)
      client.add_playlist_tracks('playlist-1', track_ids: %w[track-1 spotify:track:track-2], position: 3)
      client.replace_playlist_tracks('playlist-1', track_ids: ['track-3'])
      client.remove_playlist_tracks('playlist-1', track_ids: ['track-4'])

      assert_equal(
        [
          [:playlist, 'playlist-1'],
          [:request, [:get, '/v1/playlists/playlist-1/items', [200], { limit: 50 }], {}],
          [:request, [:post, '/v1/me/playlists', [201], { name: 'Playlist', public: false }, false], {}],
          [
            :request,
            [
              :post,
              '/v1/playlists/playlist-1/items',
              [200, 201],
              { uris: ['spotify:track:track-1', 'spotify:track:track-2'], position: 3 },
              false
            ],
            {}
          ],
          [
            :request,
            [
              :put,
              '/v1/playlists/playlist-1/items',
              [200, 201],
              { uris: ['spotify:track:track-3'] },
              false
            ],
            {}
          ],
          [
            :request,
            [
              :delete,
              '/v1/playlists/playlist-1/items',
              [200],
              { items: [{ uri: 'spotify:track:track-4' }] },
              false
            ],
            {}
          ]
        ],
        FakeSpotifyClient.last_instance.calls
      )
    end

    test 'guards playlist item request size' do
      client = Client.new(access_token: 'token', spotify_client_class: FakeSpotifyClient)

      assert_raises(ArgumentError) do
        client.add_playlist_tracks('playlist-1', track_ids: [])
      end
      assert_raises(ArgumentError) do
        client.add_playlist_tracks('playlist-1', track_ids: Array.new(101) { |index| "track-#{index}" })
      end

      assert_equal({ 'ok' => true }, client.replace_playlist_tracks('playlist-1', track_ids: []))
    end

    test 'wraps catalog search and raw request methods' do
      client = Client.new(access_token: 'token', spotify_client_class: FakeSpotifyClient)

      assert_equal [{ 'id' => 'track-1' }], client.tracks(['track-1'])
      assert_equal [{ 'id' => 'album-1' }], client.albums(['album-1'])
      assert_equal({ 'albums' => { 'items' => [] } }, client.search_album('term', limit: 10))
      assert_equal({ 'ok' => true }, client.request(:get, '/v1/me', [200]))

      assert_equal(
        [
          [:tracks, ['track-1']],
          [:albums, ['album-1']],
          [:search, :album, 'term', { limit: 10 }],
          [:request, [:get, '/v1/me', [200]], {}]
        ],
        FakeSpotifyClient.last_instance.calls
      )
    end
  end
end
