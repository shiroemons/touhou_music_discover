# frozen_string_literal: true

module Admin
  module Resources
    module PaginationHelper
      def admin_records_summary(pagy)
        total_count = pagy.count.to_i
        return t('admin.pagination.empty_summary') unless total_count.positive?

        t('admin.pagination.summary', from: pagy.from, to: pagy.to, count: total_count)
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
                    admin_pagination_link(1, t('admin.pagination.first'), disabled: pagy.page == 1, icon: :chevron_double_left),
                    admin_pagination_link(pagy.previous || 1, t('admin.pagination.prev'), disabled: pagy.previous.blank?, icon: :chevron_left),
                    tag.div(class: 'admin-pagination-pages') do
                      safe_join(admin_pagination_series(pagy).map { |item| admin_pagination_item(item, pagy.page) })
                    end,
                    admin_pagination_link(pagy.next || pagy.pages, t('admin.pagination.next'), disabled: pagy.next.blank?, icon: :chevron_right),
                    admin_pagination_link(pagy.pages, t('admin.pagination.last'), disabled: pagy.page == pagy.pages, icon: :chevron_double_right)
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
                .grep(1..pagy.pages)
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

        content = admin_pagination_link_content(label, icon)
        return tag.span(content, class: classes, aria: { current: current ? 'page' : nil }) if disabled || current

        link_to content, admin_pagination_url(page), class: classes, aria: { label: t('admin.pagination.go_to', page:) }
      end

      def admin_pagination_link_content(label, icon)
        return label if icon.blank?

        safe_join(
          [
            admin_icon(icon),
            tag.span(label, class: 'visually-hidden')
          ]
        )
      end

      def admin_pagination_url(page)
        url_for(request.query_parameters.merge(page:))
      end
    end
  end
end
