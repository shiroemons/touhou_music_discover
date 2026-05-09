# frozen_string_literal: true

require 'test_helper'

module Admin
  class ActionsHelperTest < ActionView::TestCase
    test 'renders action result bullet lines as html lists' do
      html = admin_action_result_message(<<~TEXT)
        LINE MUSIC未取得楽曲
        - 対象: 3アルバム
        - 未検出一覧:
          - Album A (JAN 1): 未取得1件
            - JPAAA000001 - Track A
            - JPAAA000002 - Track B
          - Album B (JAN 2): 未取得2件
            - JPAAA000003 - Track C
      TEXT

      assert_includes html, '<p>LINE MUSIC未取得楽曲</p>'
      assert_includes html, '<ul class="admin-action-result-list">'
      assert_includes html, '<span>未検出一覧:</span>'
      assert_includes html, '<ul class="admin-action-result-sublist">'
      assert_includes html, '<span>Album A (JAN 1): 未取得1件</span>'
      assert_includes html, '<table class="admin-action-result-detail-table">'
      assert_includes html, '<th>ISRC / ID</th>'
      assert_includes html, '<th>曲名</th>'
      assert_includes html, '<td>JPAAA000001</td>'
      assert_includes html, '<td>Track A</td>'
      assert_includes html, '<td>JPAAA000002</td>'
      assert_includes html, '<td>Track B</td>'
      assert_not_includes html, '- 未検出一覧:'
    end
  end
end
