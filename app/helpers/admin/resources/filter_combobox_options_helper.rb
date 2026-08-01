# frozen_string_literal: true

module Admin
  module Resources
    module FilterComboboxOptionsHelper
      def admin_filter_combobox_listbox(field_id, options, selected_values)
        option_groups = options.group_by { |_value, _label, group_label| group_label }

        tag.div(
          safe_join(option_groups.flat_map do |group_label, group_options|
            rendered_options = group_options.map do |value, label, _group|
              admin_filter_combobox_option(value, label, selected_values)
            end
            next rendered_options if group_label.blank?

            [
              tag.div(
                safe_join(
                  [
                    tag.div(group_label, class: 'admin-association-option-group-label', aria: { hidden: true }),
                    safe_join(rendered_options)
                  ]
                ),
                class: 'admin-association-option-group',
                role: 'group',
                aria: { label: group_label },
                data: { admin_association_select_option_group: true }
              )
            ]
          end),
          id: "#{field_id}_listbox",
          class: 'admin-association-listbox',
          role: 'listbox',
          hidden: true,
          data: { admin_association_select_target: 'listbox' }
        )
      end

      private

      def admin_filter_combobox_option(value, label, selected_values)
        tag.button(
          label,
          type: 'button',
          class: 'admin-association-option',
          role: 'option',
          aria: { selected: selected_values.include?(value.to_s) },
          data: {
            value:,
            label:,
            search_text: label,
            admin_association_select_target: 'option',
            action: 'mousedown->admin-association-select#choose'
          }
        )
      end

      def admin_filter_combobox_selection(value, label)
        tag.button(
          type: 'button',
          class: 'admin-association-selection-chip',
          aria: { label: t('admin.filters.remove_selected', label:) },
          data: {
            value:,
            action: 'mousedown->admin-association-select#remove'
          }
        ) do
          safe_join(
            [
              tag.span(label),
              tag.span('×', aria: { hidden: true })
            ]
          )
        end
      end
    end
  end
end
