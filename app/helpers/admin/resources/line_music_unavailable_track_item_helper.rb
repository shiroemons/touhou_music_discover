# frozen_string_literal: true

module Admin
  module Resources
    module LineMusicUnavailableTrackItemHelper
      private

      def admin_line_music_unavailable_track_item(track, album)
        source_titles = admin_line_music_source_titles(track, album)
        primary_title = source_titles.first
        title = primary_title&.fetch(:name) || track.name.presence || track.isrc
        alternate_titles = source_titles
                           .drop(1)
                           .reject { |source| source.fetch(:name) == title }
                           .uniq { |source| source.fetch(:name) }
        position_source = source_titles.find { |source| source.fetch(:record).track_number.present? }

        tag.li(class: 'admin-unavailable-track-item') do
          safe_join(
            [
              tag.div(class: 'admin-unavailable-track-title-group') do
                safe_join(
                  [
                    tag.span(
                      primary_title.present? ? t(
                        'admin.line_music_availability.service_title',
                        service: primary_title.fetch(:service)
                      ) : t('admin.line_music_availability.catalog_title'),
                      class: 'admin-unavailable-track-source'
                    ),
                    tag.strong(title, class: 'admin-unavailable-track-title')
                  ]
                )
              end,
              admin_line_music_alternate_titles(alternate_titles),
              admin_line_music_unavailable_track_metadata(track, position_source&.fetch(:record, nil)),
              link_to(
                t('admin.line_music_availability.show_track'),
                admin_resource_path('tracks', track),
                class: 'btn btn-sm admin-btn admin-unavailable-track-action'
              )
            ].compact
          )
        end
      end

      def admin_line_music_source_titles(track, album)
        [
          ['Apple Music', track.apple_music_track(album)],
          ['YouTube Music', track.ytmusic_track(album)],
          ['Spotify', track.spotify_track(album)]
        ].filter_map do |service, source_track|
          next if source_track&.name.blank?

          { service:, name: source_track.name, record: source_track }
        end
      end

      def admin_line_music_alternate_titles(source_titles)
        return if source_titles.empty?

        tag.dl(class: 'admin-unavailable-track-alternate-titles') do
          safe_join(
            source_titles.map do |source|
              tag.div do
                safe_join(
                  [
                    tag.dt(t('admin.line_music_availability.service_title', service: source.fetch(:service))),
                    tag.dd(source.fetch(:name))
                  ]
                )
              end
            end
          )
        end
      end

      def admin_line_music_unavailable_track_metadata(track, position_source)
        metadata = []
        if position_source&.track_number.present?
          metadata << if position_source.disc_number.present?
                        t(
                          'admin.line_music_availability.position',
                          disc_number: position_source.disc_number,
                          track_number: position_source.track_number
                        )
                      else
                        t('admin.line_music_availability.track_number', track_number: position_source.track_number)
                      end
        end
        metadata << t('admin.line_music_availability.isrc', isrc: track.isrc)

        tag.div(class: 'admin-unavailable-track-metadata') do
          safe_join(metadata.map { |item| tag.span(item) })
        end
      end
    end
  end
end
