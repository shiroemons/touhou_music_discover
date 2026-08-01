# frozen_string_literal: true

module Admin
  module Resources
    module FilterComboboxHelper
      include FilterComboboxMarkupHelper

      def admin_filter_combobox(filter, selected_value)
        field_id = "filters_#{filter[:attribute]}"
        options = filter[:options].dup
        options.unshift(['', t('admin.filters.all')]) if filter[:include_blank]
        selected_values = filter[:multiple] ? Array(selected_value).map(&:to_s).compact_blank.uniq : [selected_value.to_s]
        selected_option = options.find { |value, _label| value.to_s == selected_value.to_s }
        selected_label = selected_option&.second.to_s

        tag.div(
          class: 'admin-association-combobox admin-filter-combobox',
          data: admin_filter_combobox_data(filter)
        ) do
          safe_join(
            [
              safe_join(admin_filter_combobox_hidden_inputs(filter, selected_values, selected_value)),
              admin_filter_combobox_frame(field_id, filter, selected_label, options, selected_values),
              admin_filter_combobox_selected_markup(filter, options, selected_values)
            ]
          )
        end
      end

      private

      def admin_filter_combobox_data(filter)
        {
          controller: 'admin-association-select',
          admin_association_select_input_name_value: "filters[#{filter[:attribute]}]#{'[]' if filter[:multiple]}",
          admin_association_select_remove_label_value: t('admin.search.clear')
        }.merge(
          filter[:multiple] ? { admin_association_select_multiple_value: true } : {}
        )
      end

      def admin_filter_combobox_hidden_inputs(filter, selected_values, selected_value)
        if filter[:multiple]
          selected_values.map do |value|
            tag.input(
              type: 'hidden',
              name: "filters[#{filter[:attribute]}][]",
              value:,
              data: { admin_association_select_target: 'hidden' }
            )
          end
        else
          [tag.input(
            type: 'hidden',
            name: "filters[#{filter[:attribute]}]",
            id: "filters_#{filter[:attribute]}_value",
            value: selected_value,
            data: { admin_association_select_target: 'hidden' }
          )]
        end
      end

      def admin_filter_combobox_selected_markup(filter, options, selected_values)
        return unless filter[:multiple]

        tag.div(
          safe_join(selected_values.filter_map do |value|
            option = options.find { |option_value, _label| option_value.to_s == value }
            admin_filter_combobox_selection(value, option&.second.to_s) if option
          end),
          class: 'admin-association-selected',
          aria: { live: 'polite', atomic: true },
          data: { admin_association_select_target: 'selected' }
        )
      end
    end
  end
end
