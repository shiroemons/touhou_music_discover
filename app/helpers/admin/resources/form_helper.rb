# frozen_string_literal: true

module Admin
  module Resources
    module FormHelper
      def admin_form_field(form, resource_config, record, attribute)
        column = resource_config.column_for(attribute)
        value = record.public_send(attribute) if record.respond_to?(attribute)
        field_id = "#{resource_config.key}_#{attribute}"

        content_tag(:div, class: 'admin-field') do
          safe_join(
            [
              form.label(attribute, resource_config.attribute_label(attribute), class: 'form-label', for: field_id),
              admin_input_for(form, column, attribute, value, field_id)
            ]
          )
        end
      end

      private

      def admin_input_for(form, column, attribute, value, field_id)
        return form.text_field(attribute, value:, class: 'form-control', id: field_id) if column.blank?

        case column.type
        when :boolean
          safe_join(
            [
              form.hidden_field(attribute, value: '0'),
              tag.div(class: 'form-check form-switch') do
                form.check_box(attribute, { checked: ActiveModel::Type::Boolean.new.cast(value), class: 'form-check-input', id: field_id }, '1', '0')
              end
            ]
          )
        when :text, :json, :jsonb
          text_value = value.is_a?(String) ? value : JSON.pretty_generate(value || {})
          form.text_area(attribute, value: text_value, rows: column.type.in?(%i[json jsonb]) ? 12 : 5, class: 'form-control font-monospace', id: field_id)
        when :integer, :float, :decimal
          form.number_field(attribute, value:, step: column.type == :integer ? 1 : 'any', class: 'form-control', id: field_id)
        when :date
          form.date_field(attribute, value:, class: 'form-control', id: field_id)
        when :datetime
          form.datetime_local_field(attribute, value: value&.strftime('%Y-%m-%dT%H:%M'), class: 'form-control', id: field_id)
        else
          form.text_field(attribute, value:, class: 'form-control', id: field_id)
        end
      end
    end
  end
end
