# frozen_string_literal: true

module SpotifyWebApi
  class Client
    DEFAULT_APP_MODE = 'development'
    MAX_PLAYLIST_ITEMS_PER_REQUEST = 100

    delegate :playlist, to: :client

    def initialize(
      access_token:,
      app_mode: ENV.fetch('SPOTIFY_API_MODE', DEFAULT_APP_MODE),
      spotify_client_class: ::Spotify::Client
    )
      raise ArgumentError, 'access_token is required' if access_token.blank?

      @client = spotify_client_class.new(
        access_token:,
        app_mode:,
        raise_errors: true,
        retries: 1,
        read_timeout: 10,
        write_timeout: 10,
        persistent: false
      )
    end

    def playlist_items(playlist_id, params = {})
      request(:get, playlist_items_path(playlist_id), [200], params)
    end

    def create_playlist(name:, public: true)
      request(:post, '/v1/me/playlists', [201], { name:, public: }, false)
    end

    def add_playlist_tracks(playlist_id, track_ids:, position: nil)
      payload = { uris: track_uris(track_ids) }
      payload[:position] = position unless position.nil?

      request(:post, playlist_items_path(playlist_id), [200, 201], payload, false)
    end

    def replace_playlist_tracks(playlist_id, track_ids:)
      request(
        :put,
        playlist_items_path(playlist_id),
        [200, 201],
        { uris: track_uris(track_ids, allow_empty: true) },
        false
      )
    end

    def remove_playlist_tracks(playlist_id, track_ids:)
      items = track_uris(track_ids).map { |uri| { uri: } }
      request(:delete, playlist_items_path(playlist_id), [200], { items: }, false)
    end

    def tracks(track_ids)
      client.tracks(track_ids).fetch('tracks')
    end

    def albums(album_ids)
      client.albums(album_ids).fetch('albums')
    end

    def search_album(term, **options)
      client.search(:album, term, options)
    end

    def request(...)
      client.request!(...)
    end

    private

    attr_reader :client

    def playlist_items_path(playlist_id)
      "/v1/playlists/#{playlist_id}/items"
    end

    def track_uris(track_ids, allow_empty: false)
      uris = Array(track_ids).map do |track_id|
        track_id = track_id.to_s
        track_id.start_with?('spotify:') ? track_id : "spotify:track:#{track_id}"
      end
      raise ArgumentError, 'track_ids is required' if uris.empty? && !allow_empty
      return uris if uris.size <= MAX_PLAYLIST_ITEMS_PER_REQUEST

      raise ArgumentError, "track_ids must be #{MAX_PLAYLIST_ITEMS_PER_REQUEST} items or fewer"
    end
  end
end
