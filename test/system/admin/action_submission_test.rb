# frozen_string_literal: true

require 'application_system_test_case'

module Admin
  class ActionSubmissionTest < ApplicationSystemTestCase
    test 'submits a ready admin action from its page' do
      run_id = nil

      begin
        assert_instance_of ActiveJob::QueueAdapters::TestAdapter, Admin::ActionJob.queue_adapter

        visit admin_resource_action_path('albums', 'change_touhou_flag')

        assert_selector 'h1', text: '東方フラグを変更'
        assert_selector '.admin-action-execution-panel button[type="submit"]:not([disabled])'

        find('.admin-action-execution-panel button[type="submit"]').click
        within('dialog[open]') do
          find('button[data-action="admin-action-confirm#confirm"]').click
        end

        assert_current_path %r{/admin/albums/actions/change_touhou_flag/runs/}
        run_id = current_path.split('/').last

        assert_selector '#admin-action-progress[data-status="queued"]'
      ensure
        RedisPool.get.del("admin:action_runs:#{run_id}") if run_id
      end
    end
  end
end
