# frozen_string_literal: true

module Admin
  module Resources
    module RelationHelper
      def admin_relation_sections(resource_config, record)
        resource_config.model_class.reflect_on_all_associations.filter_map do |reflection|
          next if resource_config.hidden_relation?(reflection.name)

          Admin::RelationSection.new(resource_config:, record:, reflection:)
        end
      end

      def admin_relation_record_summary(record)
        tag.span(class: 'admin-relation-record-copy') do
          safe_join(
            [
              tag.span(admin_record_label(record), class: 'admin-relation-record-label'),
              tag.span(admin_relation_record_meta(record), class: 'admin-relation-record-meta')
            ].compact
          )
        end
      end

      def admin_record_label(record)
        %i[name title jan_code code spotify_id apple_music_id line_music_id browse_id video_id isrc id].each do |attribute|
          return record.public_send(attribute).to_s if record.respond_to?(attribute) && record.public_send(attribute).present?
        end

        record.to_param
      end

      private

      def admin_relation_record_meta(record)
        values = []
        values << admin_original_song_original_title(record)
        values << admin_track_position(record)
        values << t('admin.relations.meta.total_tracks', count: record.total_tracks) if record.respond_to?(:total_tracks) && record.total_tracks.present?
        values.compact.join(' / ').presence
      end

      def admin_original_song_original_title(record)
        return unless record.is_a?(OriginalSong) && record.original_title.present?

        t('admin.relations.meta.original', title: record.original_title)
      end

      def admin_track_position(record)
        return unless record.respond_to?(:track_number) && record.track_number.present?

        if record.respond_to?(:disc_number) && record.disc_number.present?
          t('admin.relations.meta.disc_track', disc: record.disc_number, track: record.track_number)
        else
          t('admin.relations.meta.track', track: record.track_number)
        end
      end

      def admin_reference_record(record, attribute, value)
        return if value.blank? || !attribute.to_s.end_with?('_id')

        association = attribute.to_s.delete_suffix('_id')
        reflection = record.class.reflect_on_association(association.to_sym)
        return unless reflection&.belongs_to? && record.respond_to?(association)

        associated_record = record.public_send(association)
        return associated_record if associated_record.present?

        reflection.klass.find_by(id: value)
      end

      def admin_reference_value(record)
        resource = Admin::Resource.find_by_model_class(record.class)
        content = admin_reference_content(record)

        return tag.span(content, class: 'admin-reference-card') if resource.blank?

        link_to(content, admin_resource_path(resource.key, record), class: 'admin-reference-card')
      end

      def admin_reference_content(record)
        label = admin_record_label(record)

        tag.span(class: 'admin-reference-copy') do
          safe_join(
            [
              tag.span(label, class: 'admin-reference-label'),
              tag.span(admin_reference_meta(record, label), class: 'admin-reference-meta')
            ].compact
          )
        end
      end

      def admin_record_thumbnail(record, label: admin_record_label(record))
        image_url = admin_record_image_url(record)
        return if image_url.blank?

        image_tag(image_url, alt: label, class: 'admin-record-thumb', loading: 'lazy')
      end

      def admin_record_image_url(record)
        return unless record.respond_to?(:image_url)

        record.image_url.presence
      rescue StandardError
        nil
      end

      def admin_reference_meta(record, label)
        values = %i[jan_code isrc spotify_id apple_music_id line_music_id browse_id video_id code]
                 .filter_map { |attribute| admin_record_meta_value(record, attribute) }
                 .reject { |value| value == label }
                 .first(2)
        return if values.empty?

        values.join(' / ')
      end

      def admin_record_meta_value(record, attribute)
        return unless record.respond_to?(attribute)

        record.public_send(attribute).presence&.to_s
      end
    end
  end
end
