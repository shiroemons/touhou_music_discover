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
              form.label(attribute, resource_config.attribute_label(attribute), class: 'admin-label', for: field_id),
              admin_input_for(form, resource_config, record, column, attribute, value, field_id)
            ]
          )
        end
      end

      private

      def admin_input_for(form, resource_config, record, column, attribute, value, field_id)
        return admin_readonly_input(form, column, attribute, value, field_id) if record.persisted? && resource_config.readonly_attribute?(attribute)

        association = resource_config.form_association_for(attribute)
        return admin_association_select(form, resource_config, association, value, field_id) if association.present?

        return form.text_field(attribute, value:, class: 'input admin-input', id: field_id) if column.blank?

        case column.type
        when :boolean
          safe_join(
            [
              form.hidden_field(attribute, value: '0'),
              tag.div(class: 'admin-toggle-field') do
                form.check_box(attribute, { checked: ActiveModel::Type::Boolean.new.cast(value), class: 'toggle toggle-primary', id: field_id }, '1', '0')
              end
            ]
          )
        when :text, :json, :jsonb
          text_value = value.is_a?(String) ? value : JSON.pretty_generate(value || {})
          form.text_area(attribute, value: text_value, rows: column.type.in?(%i[json jsonb]) ? 12 : 5, class: 'textarea admin-input admin-monospace', id: field_id)
        when :integer, :float, :decimal
          form.number_field(attribute, value:, step: column.type == :integer ? 1 : 'any', class: 'input admin-input', id: field_id)
        when :date
          form.date_field(attribute, value:, class: 'input admin-input', id: field_id)
        when :datetime
          form.datetime_local_field(attribute, value: value&.strftime('%Y-%m-%dT%H:%M'), class: 'input admin-input', id: field_id)
        else
          form.text_field(attribute, value:, class: 'input admin-input', id: field_id)
        end
      end

      def admin_readonly_input(form, column, attribute, value, field_id)
        classes = 'input admin-input admin-readonly-input'

        if column&.type.in?(%i[text json jsonb])
          text_value = value.is_a?(String) ? value : JSON.pretty_generate(value || {})
          form.text_area(attribute, value: text_value, rows: column.type.in?(%i[json jsonb]) ? 12 : 5, class: "textarea #{classes}", id: field_id, readonly: true)
        else
          form.text_field(attribute, value:, class: classes, id: field_id, readonly: true)
        end
      end

      def admin_association_select(form, resource_config, association, value, field_id)
        selected_option = admin_association_selected_option(association, value)
        placeholder = selected_option.present? ? t('admin.form.association_change_placeholder') : t('admin.form.association_search_placeholder')

        tag.div(
          class: 'admin-association-combobox',
          data: {
            controller: 'admin-association-select',
            admin_association_select_url_value: admin_resource_association_options_path(resource_config.key, association.foreign_key)
          }
        ) do
          safe_join(
            [
              form.hidden_field(association.foreign_key, value:, id: "#{field_id}_value", data: { admin_association_select_target: 'hidden' }),
              tag.div(class: 'admin-association-combobox-frame') do
                safe_join(
                  [
                    admin_icon(:search),
                    tag.input(
                      type: 'search',
                      id: field_id,
                      class: 'input admin-input admin-association-combobox-input',
                      placeholder:,
                      value: selected_option&.first,
                      autocomplete: 'off',
                      role: 'combobox',
                      aria: { autocomplete: 'list', expanded: false, controls: "#{field_id}_listbox" },
                      data: {
                        admin_association_select_target: 'input',
                        action: [
                          'focus->admin-association-select#focus',
                          'input->admin-association-select#filter',
                          'keydown->admin-association-select#keydown',
                          'blur->admin-association-select#blur'
                        ].join(' ')
                      }
                    ),
                    tag.div(
                      nil,
                      id: "#{field_id}_listbox",
                      class: 'admin-association-listbox',
                      role: 'listbox',
                      hidden: true,
                      data: { admin_association_select_target: 'listbox' }
                    )
                  ]
                )
              end
            ]
          )
        end
      end

      def admin_association_selected_option(association, value)
        return if value.blank?

        record = association.klass.find_by(association.association_primary_key => value)
        return if record.blank?

        [Admin::AssociationOption.label(record), record.public_send(association.association_primary_key)]
      end
    end
  end
end
