# frozen_string_literal: true

module Admin
  module Resources
    module FormInputHelper
      include AssociationFormHelper

      private

      def admin_input_for(form, resource_config, record, attribute, field_options: {})
        column = resource_config.column_for(attribute)
        value = record.public_send(attribute) if record.respond_to?(attribute)
        field_id = admin_field_id(resource_config, attribute)

        if record.persisted? && resource_config.readonly_attribute?(attribute)
          return admin_readonly_input(
            form,
            column,
            attribute,
            value,
            field: { id: field_id, options: field_options }
          )
        end

        association = resource_config.form_association_for(attribute)
        if association.present?
          return admin_association_select(
            form,
            resource_config,
            association,
            field: { id: field_id, options: field_options, value: }
          )
        end

        return form.text_field(attribute, value:, class: 'input admin-input', id: field_id, **field_options) if column.blank?

        case column.type
        when :boolean
          safe_join(
            [
              form.hidden_field(attribute, value: '0'),
              tag.div(class: 'admin-toggle-field') do
                form.check_box(
                  attribute,
                  { checked: ActiveModel::Type::Boolean.new.cast(value), class: 'toggle toggle-primary', id: field_id }.merge(field_options),
                  '1',
                  '0'
                )
              end
            ]
          )
        when :text, :json, :jsonb
          text_value = value.is_a?(String) ? value : JSON.pretty_generate(value || {})
          form.text_area(
            attribute,
            value: text_value,
            rows: column.type.in?(%i[json jsonb]) ? 12 : 5,
            class: 'textarea admin-input admin-monospace',
            id: field_id,
            **field_options
          )
        when :integer, :float, :decimal
          form.number_field(
            attribute,
            value:,
            step: column.type == :integer ? 1 : 'any',
            class: 'input admin-input',
            id: field_id,
            **field_options
          )
        when :date
          form.date_field(attribute, value:, class: 'input admin-input', id: field_id, **field_options)
        when :datetime
          form.datetime_local_field(
            attribute,
            value: value&.strftime('%Y-%m-%dT%H:%M'),
            class: 'input admin-input',
            id: field_id,
            **field_options
          )
        else
          form.text_field(attribute, value:, class: 'input admin-input', id: field_id, **field_options)
        end
      end

      def admin_readonly_input(form, column, attribute, value, field:)
        field_id = field.fetch(:id)
        field_options = field.fetch(:options, {})
        classes = 'input admin-input admin-readonly-input'

        if column&.type.in?(%i[text json jsonb])
          text_value = value.is_a?(String) ? value : JSON.pretty_generate(value || {})
          form.text_area(
            attribute,
            value: text_value,
            rows: column.type.in?(%i[json jsonb]) ? 12 : 5,
            class: "textarea #{classes}",
            id: field_id,
            readonly: true,
            **field_options
          )
        else
          form.text_field(attribute, value:, class: classes, id: field_id, readonly: true, **field_options)
        end
      end
    end
  end
end
