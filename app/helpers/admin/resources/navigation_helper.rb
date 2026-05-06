# frozen_string_literal: true

module Admin
  module Resources
    module NavigationHelper
      def admin_active_filters?(resource_config, active_filters)
        params[:q].present? || resource_config.non_default_filters?(active_filters)
      end

      def admin_infinite_scroll?
        params[:scroll].to_s == 'infinite'
      end

      def admin_scroll_mode_path(mode)
        query = request.query_parameters.merge(page: nil)
        query[:scroll] = mode.to_s == 'infinite' ? 'infinite' : nil

        url_for(query.compact)
      end

      def admin_clear_filters_path(resource_config)
        query = admin_infinite_scroll? ? { scroll: 'infinite' } : {}

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

      def admin_pagination(pagy)
        return if pagy.pages <= 1

        tag.nav(class: 'admin-pagination', aria: { label: t('admin.pagination.aria_label') }) do
          safe_join(
            [
              tag.div(
                t('admin.pagination.summary', from: pagy.from, to: pagy.to, count: pagy.count),
                class: 'admin-pagination-summary'
              ),
              tag.div(class: 'admin-pagination-controls') do
                safe_join(
                  [
                    admin_pagination_link(1, t('admin.pagination.first'), disabled: pagy.page == 1, icon: 'bi-chevron-double-left'),
                    admin_pagination_link(pagy.prev || 1, t('admin.pagination.prev'), disabled: pagy.prev.blank?, icon: 'bi-chevron-left'),
                    tag.div(class: 'admin-pagination-pages') do
                      safe_join(admin_pagination_series(pagy).map { |item| admin_pagination_item(item, pagy.page) })
                    end,
                    admin_pagination_link(pagy.next || pagy.pages, t('admin.pagination.next'), disabled: pagy.next.blank?, icon: 'bi-chevron-right'),
                    admin_pagination_link(pagy.pages, t('admin.pagination.last'), disabled: pagy.page == pagy.pages, icon: 'bi-chevron-double-right')
                  ]
                )
              end
            ]
          )
        end
      end

      private

      def admin_pagination_series(pagy)
        pages = ([1, pagy.pages] + ((pagy.page - 2)..(pagy.page + 2)).to_a)
                .select { |page| page.between?(1, pagy.pages) }
                .uniq
                .sort

        pages.each_cons(2).with_object([pages.first]) do |(previous_page, next_page), series|
          series << :gap if next_page - previous_page > 1
          series << next_page
        end
      end

      def admin_pagination_item(item, current_page)
        return tag.span('...', class: 'admin-pagination-gap', aria: { hidden: true }) if item == :gap

        admin_pagination_link(item, item.to_s, current: item == current_page)
      end

      def admin_pagination_link(page, label, disabled: false, current: false, icon: nil)
        classes = ['admin-pagination-link']
        classes << 'is-current' if current
        classes << 'is-disabled' if disabled

        content = if icon
                    safe_join(
                      [
                        tag.i(class: "bi #{icon}", aria: { hidden: true }),
                        tag.span(label, class: 'visually-hidden')
                      ]
                    )
                  else
                    label
                  end

        return tag.span(content, class: classes, aria: { current: current ? 'page' : nil }) if disabled || current

        link_to content, admin_pagination_url(page), class: classes, aria: { label: t('admin.pagination.go_to', page:) }
      end

      def admin_pagination_url(page)
        url_for(request.query_parameters.merge(page:))
      end
    end
  end
end
