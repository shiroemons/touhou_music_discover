# frozen_string_literal: true

module Admin
  module Resources
    module LineMusicUnavailableTracksHelper
      private

      def admin_line_music_unavailable_tracks_value(record)
        return tag.span(t('admin.shared.blank'), class: 'admin-muted-text') unless record.is_a?(LineMusicAlbum)
        return tag.span(t('admin.line_music_availability.none'), class: 'admin-muted-text') unless record.catalog_availability_status == :shortage

        unless record.track_sync_complete?
          return tag.span(
            t(
              'admin.line_music_availability.pending',
              fetched_count: record.line_music_tracks.size,
              line_count: record.total_tracks.to_i
            ),
            class: 'admin-muted-text'
          )
        end

        unavailable_tracks = record.unavailable_catalog_tracks
        return tag.span(t('admin.line_music_availability.ambiguous'), class: 'badge badge-warning') unless unavailable_tracks.size == record.unavailable_track_count

        heading_id = dom_id(record, :unavailable_tracks_heading)
        tag.section(class: 'admin-unavailable-track-panel', aria: { labelledby: heading_id }) do
          safe_join(
            [
              admin_line_music_unavailable_tracks_header(record, heading_id),
              tag.p(
                t(
                  'admin.line_music_availability.summary',
                  catalog_count: record.catalog_track_count,
                  line_count: record.total_tracks.to_i
                ),
                class: 'admin-unavailable-track-summary'
              ),
              tag.ol(class: 'admin-unavailable-track-list') do
                safe_join(
                  unavailable_tracks.map do |track|
                    admin_line_music_unavailable_track_item(track, record.album)
                  end
                )
              end
            ]
          )
        end
      end

      def admin_line_music_unavailable_tracks_header(record, heading_id)
        tag.div(class: 'admin-unavailable-track-header') do
          safe_join(
            [
              tag.span(admin_icon(:warning), class: 'admin-unavailable-track-icon'),
              tag.div do
                safe_join(
                  [
                    tag.span(
                      t('admin.line_music_availability.shortage', count: record.unavailable_track_count),
                      class: 'badge badge-warning'
                    ),
                    tag.h3(
                      t('admin.line_music_availability.heading'),
                      id: heading_id,
                      class: 'admin-unavailable-track-heading'
                    )
                  ]
                )
              end
            ]
          )
        end
      end
    end
  end
end
