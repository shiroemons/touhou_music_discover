# frozen_string_literal: true

module Admin
  class AssociationOption
    class << self
      def as_json(record, primary_key:)
        {
          value: record.public_send(primary_key).to_s,
          label: label(record)
        }
      end

      def label(record)
        return album_label(record) if record.is_a?(Album)
        return track_label(record) if record.is_a?(Track)

        base_label = record_label(record)
        [base_label, reference_meta(record, base_label)].compact_blank.join(' / ')
      end

      private

      def album_label(record)
        [
          record.jan_code,
          record.circle_name,
          record.spotify_album_name,
          record.apple_music_album_name,
          record.ytmusic_album_name,
          record.line_music_album_name
        ].compact_blank.uniq.join(' / ')
      end

      def track_label(record)
        [
          record.name,
          record.jan_code,
          record.isrc,
          record.album_name,
          record.circle_name
        ].compact_blank.uniq.join(' / ')
      end

      def record_label(record)
        %i[name title jan_code code spotify_id apple_music_id line_music_id browse_id video_id isrc id].each do |attribute|
          value = record.public_send(attribute) if record.respond_to?(attribute)
          return value.to_s if value.present?
        end

        record.to_param
      end

      def reference_meta(record, label)
        values = %i[jan_code isrc spotify_id apple_music_id line_music_id browse_id video_id code]
                 .filter_map { |attribute| record.public_send(attribute).presence&.to_s if record.respond_to?(attribute) }
                 .reject { |value| value == label }
                 .first(2)

        values.join(' / ').presence
      end
    end
  end
end
