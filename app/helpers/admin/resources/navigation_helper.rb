# frozen_string_literal: true

module Admin
  module Resources
    module NavigationHelper
      def admin_active_filters?(resource_config, active_filters)
        params[:q].present? || resource_config.non_default_filters?(active_filters)
      end

      def admin_active_filter_chips(resource_config, active_filters)
        chips = []
        chips << [t('admin.search.query'), params[:q]] if params[:q].present?

        resource_config.filters.each do |filter|
          value = active_filters[filter[:attribute]]
          next if value.blank? || value == filter[:default]

          option = filter[:options].find { |option_value, _label| option_value.to_s == value.to_s }
          chips << [filter[:label], option&.second || value]
        end

        chips
      end

      def admin_infinite_scroll?
        params[:scroll].to_s != 'pagination'
      end

      def admin_scroll_mode_path(mode)
        query = request.query_parameters.merge(page: nil)
        query[:scroll] = mode.to_s == 'pagination' ? 'pagination' : nil

        url_for(query.compact)
      end

      def admin_clear_filters_path(resource_config)
        query = admin_infinite_scroll? ? {} : { scroll: 'pagination' }

        admin_resources_path(resource_config.key, query)
      end

      def admin_infinite_scroll_next_url(pagy)
        return if pagy.next.blank?

        url_for(request.query_parameters.merge(page: pagy.next, scroll: 'infinite'))
      end

      def admin_resource_actions(resource_config, record: nil)
        resource_config.actions.select do |action|
          record.present? ? action.member? : action.collection?
        end
      end

      def admin_sortable_header(resource_config, attribute)
        label = resource_config.index_attribute_label(attribute)
        return label unless resource_config.sortable_attribute?(attribute)

        current = params[:sort].to_s == attribute.to_s
        direction = resource_config.sort_direction(params[:direction])
        next_direction = current && direction == 'asc' ? 'desc' : 'asc'
        classes = ['admin-sort-link']
        classes << 'is-active' if current

        link_to admin_sort_url(attribute, next_direction), class: classes, aria: { sort: admin_sort_aria(current, direction) } do
          safe_join(
            [
              tag.span(label),
              tag.span(current ? admin_sort_indicator(direction) : '', class: 'admin-sort-indicator', aria: { hidden: true })
            ]
          )
        end
      end

      private

      def admin_sort_url(attribute, direction)
        url_for(request.query_parameters.merge(sort: attribute, direction:, page: nil).compact)
      end

      def admin_sort_aria(current, direction)
        return nil unless current

        direction == 'desc' ? 'descending' : 'ascending'
      end

      def admin_sort_indicator(direction)
        admin_icon(direction == 'desc' ? :chevron_down : :chevron_up)
      end
    end
  end
end
