# frozen_string_literal: true

module Admin
  module Resources
    module FilterComboboxMarkupHelper
      include FilterComboboxOptionsHelper

      def admin_filter_combobox_frame(field_id, filter, selected_label, options, selected_values)
        tag.div(class: 'admin-association-combobox-frame') do
          safe_join(
            [
              admin_icon(:search),
              admin_filter_combobox_input(field_id, filter, selected_label),
              admin_filter_combobox_listbox(field_id, options, selected_values)
            ]
          )
        end
      end

      private

      def admin_filter_combobox_input(field_id, filter, selected_label)
        tag.input(
          type: 'search',
          id: field_id,
          class: 'input admin-input admin-association-combobox-input',
          placeholder: t('admin.filters.search_placeholder'),
          value: filter[:multiple] ? '' : selected_label,
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
    end
  end
end
