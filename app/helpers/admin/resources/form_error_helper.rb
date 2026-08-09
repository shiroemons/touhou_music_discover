# frozen_string_literal: true

module Admin
  module Resources
    module FormErrorHelper
      def admin_form_error_messages(record, resource_config, attribute)
        error_attributes = [attribute.to_s]
        association = resource_config.form_association_for(attribute)
        error_attributes << association.name.to_s if association.present?

        error_attributes.flat_map { |error_attribute| record.errors.full_messages_for(error_attribute) }.uniq
      end

      def admin_field_input_options(field_errors, field_error_id)
        return {} if field_errors.empty?

        { aria: { invalid: true, describedby: field_error_id } }
      end

      def admin_field_errors(field_errors, field_error_id)
        return if field_errors.empty?

        tag.ul(id: field_error_id, class: 'admin-field-error-list') do
          safe_join(field_errors.map { |message| tag.li(message) })
        end
      end

      def admin_field_error_id(resource_config, attribute)
        "#{admin_field_id(resource_config, attribute)}_error"
      end
    end
  end
end
