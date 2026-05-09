# frozen_string_literal: true

module Admin
  module Resources
    module AssociationFormHelper
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
              admin_association_combobox_frame(field_id, placeholder, selected_option)
            ]
          )
        end
      end

      private

      def admin_association_combobox_frame(field_id, placeholder, selected_option)
        tag.div(class: 'admin-association-combobox-frame') do
          safe_join(
            [
              admin_icon(:search),
              admin_association_search_input(field_id, placeholder, selected_option),
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
      end

      def admin_association_search_input(field_id, placeholder, selected_option)
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
        )
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
