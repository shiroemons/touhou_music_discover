# frozen_string_literal: true

module Admin
  module ActionsHelper
    def admin_action_result_message(message)
      lines = message.to_s.lines.map(&:chomp).compact_blank
      blocks = []
      list_items = []

      flush_list = lambda do
        next if list_items.empty?

        blocks << tag.ul(safe_join(list_items), class: 'admin-action-result-list')
        list_items = []
      end

      index = 0
      while index < lines.size
        line = lines[index]

        if line.start_with?('- ')
          item, index = admin_action_result_list_item(lines, index)
          list_items << item
        else
          flush_list.call
          blocks << tag.p(line)
          index += 1
        end
      end

      flush_list.call
      safe_join(blocks)
    end

    private

    def admin_action_result_list_item(lines, index)
      label = lines[index].delete_prefix('- ')
      nested_items = []
      next_index = index + 1

      while next_index < lines.size && lines[next_index].start_with?('  - ')
        nested_item, next_index = admin_action_result_nested_list_item(lines, next_index)
        nested_items << nested_item
      end

      contents = [tag.span(label)]
      if nested_items.any?
        contents << tag.ul(
          safe_join(nested_items),
          class: 'admin-action-result-sublist'
        )
      end

      [tag.li(safe_join(contents)), next_index]
    end

    def admin_action_result_nested_list_item(lines, index)
      label = lines[index].delete_prefix('  - ')
      detail_items = []
      next_index = index + 1

      while next_index < lines.size && lines[next_index].start_with?('    - ')
        detail_items << lines[next_index].delete_prefix('    - ')
        next_index += 1
      end

      contents = [tag.span(label)]
      contents << admin_action_result_detail_table(detail_items) if detail_items.any?

      [tag.li(safe_join(contents)), next_index]
    end

    def admin_action_result_detail_table(detail_items)
      rows = detail_items.map do |item|
        identifier, name = admin_action_result_detail_columns(item)
        tag.tr do
          safe_join([
                      tag.td(identifier),
                      tag.td(name)
                    ])
        end
      end

      tag.table(class: 'admin-action-result-detail-table') do
        safe_join([
                    tag.thead do
                      tag.tr do
                        safe_join([
                                    tag.th('ISRC / ID'),
                                    tag.th('曲名')
                                  ])
                      end
                    end,
                    tag.tbody(safe_join(rows))
                  ])
      end
    end

    def admin_action_result_detail_columns(item)
      identifier, name = item.split(' - ', 2)
      return [identifier, name] if name.present?

      ['', item]
    end
  end
end
