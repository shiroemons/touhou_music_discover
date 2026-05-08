# frozen_string_literal: true

module Admin
  module Resources
    module ExternalLinksHelper
      STREAMING_ALBUM_EXTERNAL_LINKS = {
        'spotify_albums' => { label: 'Spotify', url: 'https://open.spotify.com/', url_attributes: %i[url] },
        'apple_music_albums' => { label: 'Apple Music', url: 'https://music.apple.com/jp/browse', url_attributes: %i[url] },
        'ytmusic_albums' => { label: 'YouTube Music', url: 'https://music.youtube.com/', url_attributes: %i[url playlist_url] },
        'line_music_albums' => { label: 'LINE MUSIC', url: 'https://music.line.me/webapp', url_attributes: %i[url] }
      }.freeze

      def admin_collection_external_album_links(resource_config)
        case resource_config.key
        when 'albums'
          STREAMING_ALBUM_EXTERNAL_LINKS.values.map { |config| admin_external_album_link(config, config.fetch(:url)) }
        when *STREAMING_ALBUM_EXTERNAL_LINKS.keys
          config = STREAMING_ALBUM_EXTERNAL_LINKS.fetch(resource_config.key)
          [admin_external_album_link(config, config.fetch(:url))]
        else
          []
        end
      end

      def admin_external_album_links(resource_config, record)
        config = STREAMING_ALBUM_EXTERNAL_LINKS[resource_config.key]
        return [] if config.blank?

        url = config.fetch(:url_attributes).filter_map do |attribute|
          next unless record.respond_to?(attribute)

          candidate = record.public_send(attribute).to_s
          candidate if candidate.start_with?('http')
        end.first
        return [] if url.blank?

        [admin_external_album_link(config, url)]
      end

      def admin_external_album_link(config, url)
        { label: config.fetch(:label), url: }
      end
    end
  end
end
