# frozen_string_literal: true

module Admin
  module Resources
    module StatusHelper
      STREAMING_TRACK_STATUS_ACTIONS = {
        'SpotifyAlbum' => {
          association: :spotify_tracks,
          resource_key: 'spotify_albums',
          action_key: 'fetch_spotify_album'
        },
        'AppleMusicAlbum' => {
          association: :apple_music_tracks,
          resource_key: 'apple_music_tracks',
          action_key: 'fetch_apple_music_track'
        },
        'LineMusicAlbum' => {
          association: :line_music_tracks,
          resource_key: 'line_music_tracks',
          action_key: 'fetch_line_music_track'
        },
        'YtmusicAlbum' => {
          association: :ytmusic_tracks,
          resource_key: 'ytmusic_tracks',
          action_key: 'fetch_ytmusic_track'
        }
      }.freeze
      TRACK_STREAMING_SERVICES = {
        spotify: { label: 'Spotify', association: :spotify_tracks },
        apple_music: { label: 'Apple Music', association: :apple_music_tracks },
        line_music: { label: 'LINE MUSIC', association: :line_music_tracks },
        ytmusic: { label: 'YouTube Music', association: :ytmusic_tracks }
      }.freeze

      private

      def admin_tracks_status_value(record)
        action_config = STREAMING_TRACK_STATUS_ACTIONS[record.class.name]
        return tag.span(t('admin.shared.blank'), class: 'text-body-secondary') if action_config.blank?

        track_count = record.public_send(action_config.fetch(:association)).size
        total_tracks = record.respond_to?(:total_tracks) ? record.total_tracks.to_i : 0
        status_key = admin_tracks_status_key(track_count, total_tracks)
        count_label = total_tracks.positive? ? "#{track_count} / #{total_tracks}" : track_count.to_s

        tag.div(class: 'admin-track-status') do
          safe_join(
            [
              tag.span(count_label, class: 'admin-track-status-count'),
              tag.span(t("admin.track_status.#{status_key}"), class: "badge #{admin_tracks_status_badge_class(status_key)}"),
              admin_tracks_status_action_link(action_config, status_key)
            ].compact
          )
        end
      end

      def admin_tracks_status_key(track_count, total_tracks)
        return :missing if track_count.zero?
        return :incomplete if total_tracks.positive? && track_count < total_tracks
        return :complete if total_tracks.positive? && track_count >= total_tracks

        :present
      end

      def admin_tracks_status_badge_class(status_key)
        {
          missing: 'text-bg-danger',
          incomplete: 'text-bg-warning',
          complete: 'text-bg-success',
          present: 'text-bg-secondary'
        }.fetch(status_key)
      end

      def admin_tracks_status_action_link(action_config, status_key)
        return unless status_key.in?(%i[missing incomplete])

        link_to admin_resource_action_path(action_config.fetch(:resource_key), action_config.fetch(:action_key)),
                class: 'btn btn-sm admin-btn admin-track-status-action' do
          safe_join(
            [
              tag.i(class: 'bi bi-lightning-charge', aria: { hidden: true }),
              tag.span(t('admin.track_status.action'))
            ]
          )
        end
      end

      def admin_streaming_tracks_status_value(record)
        missing_services = TRACK_STREAMING_SERVICES.filter do |_key, service|
          record.respond_to?(service.fetch(:association)) && record.public_send(service.fetch(:association)).empty?
        end

        return tag.span(t('admin.streaming_status.complete'), class: 'badge text-bg-success') if missing_services.empty?

        tag.div(class: 'admin-streaming-status') do
          safe_join(
            missing_services.map do |key, service|
              link_to(
                t('admin.streaming_status.missing', service: service.fetch(:label)),
                admin_resources_path('tracks', filters: { missing_streaming_track: key }),
                class: 'badge text-bg-warning admin-streaming-status-badge'
              )
            end
          )
        end
      end
    end
  end
end
