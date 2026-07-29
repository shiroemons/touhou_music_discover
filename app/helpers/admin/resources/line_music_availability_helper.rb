# frozen_string_literal: true

module Admin
  module Resources
    module LineMusicAvailabilityHelper
      private

      def admin_line_music_album_index_value(line_music_album, value)
        content = if admin_record_image_url(line_music_album).present?
                    admin_value_with_thumbnail(line_music_album, value)
                  else
                    value.to_s
                  end
        associated_resource = Admin::Resource.find_by_model_class(line_music_album.class)
        album_link = if associated_resource.present?
                       link_to(
                         content,
                         admin_resource_path(associated_resource.key, line_music_album),
                         class: 'admin-index-record-link'
                       )
                     else
                       content
                     end

        tag.div(class: 'admin-line-music-album-value') do
          safe_join(
            [
              album_link,
              admin_line_music_availability_badge(line_music_album, show_complete: false)
            ].compact
          )
        end
      end

      def admin_line_music_catalog_availability_value(record)
        return tag.span(t('admin.shared.blank'), class: 'admin-muted-text') unless record.is_a?(LineMusicAlbum)

        tag.div(class: 'admin-catalog-availability') do
          safe_join(
            [
              tag.span(
                t(
                  'admin.line_music_availability.counts',
                  line_count: record.total_tracks.to_i,
                  catalog_count: record.catalog_track_count
                ),
                class: 'admin-catalog-availability-counts'
              ),
              admin_line_music_availability_badge(record)
            ]
          )
        end
      end

      def admin_line_music_availability_badge(record, show_complete: true)
        status = record.catalog_availability_status
        return if !show_complete && status.in?(%i[complete unknown])

        label, badge_class = case status
                             when :shortage
                               [
                                 t('admin.line_music_availability.shortage', count: record.unavailable_track_count),
                                 'badge-warning'
                               ]
                             when :excess
                               [t('admin.line_music_availability.excess'), 'badge-warning']
                             when :complete
                               [t('admin.line_music_availability.complete'), 'badge-success']
                             else
                               [t('admin.line_music_availability.unknown'), 'badge-neutral']
                             end

        tag.span(label, class: "badge #{badge_class}")
      end
    end
  end
end
