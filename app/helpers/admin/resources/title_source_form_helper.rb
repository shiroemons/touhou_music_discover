# frozen_string_literal: true

module Admin
  module Resources
    module TitleSourceFormHelper
      private

      def admin_title_source_override_input(form, attribute, field_id, field_options)
        options = [[I18n.t('admin.values.album_title_source.automatic'), '']] + Album::TITLE_SOURCE_OPTIONS.map do |source|
          [I18n.t("admin.values.album_title_source.#{source}"), source]
        end

        form.select(
          attribute,
          options,
          {},
          class: 'select admin-input admin-title-source-select',
          id: field_id,
          **field_options
        )
      end
    end
  end
end
