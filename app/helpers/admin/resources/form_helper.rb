# frozen_string_literal: true

module Admin
  module Resources
    module FormHelper
      include FormErrorHelper
      include FormInputHelper

      def admin_form_field(form, resource_config, record, attribute)
        field_id = admin_field_id(resource_config, attribute)
        field_errors = admin_form_error_messages(record, resource_config, attribute)
        field_error_id = admin_field_error_id(resource_config, attribute)
        help_id = admin_field_help_id(resource_config, attribute)
        field_options = admin_field_input_options(field_errors, field_error_id)
        if admin_field_help_text(record, attribute).present?
          field_options[:aria] = field_options.fetch(:aria, {}).merge(
            describedby: [field_options.dig(:aria, :describedby), help_id].compact.join(' ')
          )
        end

        content_tag(:div, class: ['admin-field', ('has-error' if field_errors.any?)].compact.join(' ')) do
          safe_join(
            [
              form.label(attribute, resource_config.attribute_label(attribute), class: 'admin-label', for: field_id),
              admin_input_for(
                form,
                resource_config,
                record,
                attribute,
                field_options:
              ),
              (tag.p(admin_field_help_text(record, attribute), id: help_id, class: 'admin-field-help') if admin_field_help_text(record, attribute).present?),
              admin_field_errors(field_errors, field_error_id)
            ]
          )
        end
      end

      private

      def admin_field_id(resource_config, attribute)
        "#{resource_config.key}_#{attribute}"
      end

      def admin_field_help_id(resource_config, attribute)
        "#{admin_field_id(resource_config, attribute)}_help"
      end

      def admin_field_help_text(record, attribute)
        return unless record.is_a?(Album) && attribute.to_s == 'title_source_override'

        t('admin.form.title_source_override_help')
      end
    end
  end
end
