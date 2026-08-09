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

        content_tag(:div, class: ['admin-field', ('has-error' if field_errors.any?)].compact.join(' ')) do
          safe_join(
            [
              form.label(attribute, resource_config.attribute_label(attribute), class: 'admin-label', for: field_id),
              admin_input_for(
                form,
                resource_config,
                record,
                attribute,
                field_options: admin_field_input_options(field_errors, field_error_id)
              ),
              admin_field_errors(field_errors, field_error_id)
            ]
          )
        end
      end

      private

      def admin_field_id(resource_config, attribute)
        "#{resource_config.key}_#{attribute}"
      end
    end
  end
end
