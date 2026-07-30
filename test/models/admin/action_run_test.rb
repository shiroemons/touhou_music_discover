# frozen_string_literal: true

require 'test_helper'

module Admin
  class ActionRunTest < ActiveSupport::TestCase
    setup do
      @run_id = SecureRandom.uuid
    end

    teardown do
      RedisPool.get.del("admin:action_runs:#{@run_id}")
    end

    test 'creates a queued run before the background job starts' do
      Admin::ActionRun.create!(
        run_id: @run_id,
        resource_key: 'albums',
        action_key: 'change_touhou_flag',
        action_label: '東方フラグを変更',
        redirect_path: '/admin/albums'
      )

      action_run = Admin::ActionRun.find!(@run_id)

      assert_equal 'queued', action_run.fetch('status')
      assert_equal I18n.t('admin.actions.progress.queued'), action_run.fetch('message')
      assert_predicate action_run.fetch('enqueued_at'), :present?
      assert_nil action_run.fetch('started_at')
      assert Admin::ActionRun.active_status?(action_run.fetch('status'))
    end

    test 'marks a queued run as processing when the background job starts' do
      create_action_run

      Admin::ActionRun.start!(@run_id)
      action_run = Admin::ActionRun.find!(@run_id)

      assert_equal 'processing', action_run.fetch('status')
      assert_equal I18n.t('admin.actions.progress.started'), action_run.fetch('message')
      assert_predicate action_run.fetch('started_at'), :present?
      assert Admin::ActionRun.active_status?(action_run.fetch('status'))
    end

    test 'recognizes only queued and processing runs as active' do
      assert Admin::ActionRun.active_status?('queued')
      assert Admin::ActionRun.active_status?('processing')
      assert_not Admin::ActionRun.active_status?('completed')
      assert_not Admin::ActionRun.active_status?('error')
    end

    private

    def create_action_run
      Admin::ActionRun.create!(
        run_id: @run_id,
        resource_key: 'albums',
        action_key: 'change_touhou_flag',
        action_label: '東方フラグを変更',
        redirect_path: '/admin/albums'
      )
    end
  end
end
