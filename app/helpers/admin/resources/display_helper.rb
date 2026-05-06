# frozen_string_literal: true

module Admin
  module Resources
    module DisplayHelper
      def admin_display_value(resource_config, record, attribute)
        return admin_tracks_status_value(record) if attribute.to_s == 'tracks_status'
        return admin_streaming_tracks_status_value(record) if attribute.to_s == 'streaming_tracks_status'

        value = resource_config.value_for(record, attribute)
        reference_record = admin_reference_record(record, attribute, value)
        return admin_reference_value(reference_record) if reference_record

        case value
        when TrueClass
          tag.span('true', class: 'badge text-bg-success')
        when FalseClass
          tag.span('false', class: 'badge text-bg-secondary')
        when Hash, Array
          tag.pre(admin_pretty_json(value), class: 'admin-json-block')
        when Time, DateTime
          value.in_time_zone('Asia/Tokyo').strftime('%Y-%m-%d %H:%M:%S')
        when Date
          value.iso8601
        else
          admin_scalar_value(record, attribute, value)
        end
      end

      def admin_index_display_value(resource_config, record, attribute)
        value = resource_config.value_for(record, attribute)
        content = admin_display_value(resource_config, record, attribute)
        return content unless admin_linkable_index_attribute?(resource_config, attribute, value)

        link_to(content, admin_resource_path(resource_config.key, record), class: 'admin-index-record-link')
      end

      private

      def admin_linkable_index_attribute?(resource_config, attribute, value)
        return false if value.blank?
        return false unless Admin::Resource.find_by_model_class(resource_config.model_class)

        attribute.to_s.in?(%w[name title short_title album_name spotify_album_name apple_music_album_name ytmusic_album_name line_music_album_name])
      end

      def admin_pretty_json(value)
        JSON.pretty_generate(value)
      rescue JSON::GeneratorError
        value.to_s
      end

      def admin_scalar_value(record, attribute, value)
        return tag.span(t('admin.shared.blank'), class: 'text-body-secondary') if value.blank?
        return link_to(value, value, target: '_blank', rel: 'noopener') if attribute.to_s.end_with?('url') && value.to_s.start_with?('http')
        return admin_value_with_thumbnail(record, value) if admin_thumbnail_attribute?(attribute) && admin_record_image_url(record).present?

        value.to_s
      end

      def admin_thumbnail_attribute?(attribute)
        attribute.to_s.in?(%w[name title album_name spotify_album_name apple_music_album_name ytmusic_album_name line_music_album_name])
      end

      def admin_value_with_thumbnail(record, value)
        tag.span(class: 'admin-value-with-thumb') do
          safe_join(
            [
              admin_record_thumbnail(record, label: value.to_s),
              tag.span(value.to_s, class: 'admin-value-label')
            ]
          )
        end
      end
    end
  end
end
