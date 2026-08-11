# frozen_string_literal: true

module Admin
  module Resources
    module TitleSourceDisplayHelper
      private

      def admin_album_title_source_value(record, attribute, value)
        resolution = record.display_title_resolution
        source = attribute.to_s == 'display_title_source' ? resolution.source : value.presence
        key = source || (attribute.to_s == 'display_title_source' ? 'unavailable' : 'automatic')
        label = t("admin.values.album_title_source.#{key}", default: key.to_s)
        status = if attribute.to_s == 'display_title_source'
                   if resolution.override?
                     'override'
                   elsif resolution.fallback?
                     'fallback'
                   else
                     'automatic'
                   end
                 else
                   value.present? ? 'override' : 'automatic'
                 end

        tag.span(label, class: ['badge', "admin-title-source-#{status}"])
      end
    end
  end
end
