# frozen_string_literal: true

require 'test_helper'

module Admin
  class DashboardControllerTest < ActionDispatch::IntegrationTest
    test 'shows admin dashboard without depending on avo routes' do
      get admin_root_url

      assert_response :success
      assert_select 'h1', '管理画面'
      assert_select 'a[href=?]', '/avo', text: 'Avo'
      assert_select 'a[href=?]', admin_resources_path('albums'), text: 'アルバム'
      assert_select 'a[href=?]', admin_new_resource_path('albums'), text: '新規作成'
    end
  end
end
