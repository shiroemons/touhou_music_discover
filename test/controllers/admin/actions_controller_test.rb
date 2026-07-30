# frozen_string_literal: true

require 'test_helper'

module Admin
  class ActionsControllerTest < ActionDispatch::IntegrationTest
    include ActiveJob::TestHelper

    teardown do
      clear_enqueued_jobs
      clear_performed_jobs
    end

    test 'enqueues admin action job when running an action' do
      created_run = nil

      with_action_run_method(:create!, ->(**attrs) { created_run = attrs }) do
        assert_enqueued_with(job: Admin::ActionJob, queue: 'admin_actions') do
          post admin_resource_action_url('albums', 'change_touhou_flag')
        end
      end

      assert_response :redirect
      assert_match(%r{/admin/albums/actions/change_touhou_flag/runs/}, response.location)
      assert_equal 'albums', created_run.fetch(:resource_key)
      assert_equal 'change_touhou_flag', created_run.fetch(:action_key)
    end

    test 'shows a queued action without presenting it as running' do
      run_id = create_action_run

      get admin_resource_action_run_url('albums', 'change_touhou_flag', run_id)

      assert_response :success
      assert_select '#admin-action-progress[data-status="queued"][data-polling="true"]'
      assert_select '#admin-action-progress h2', text: I18n.t('admin.actions.progress.statuses.queued')
      assert_select '.admin-action-progress-percent', text: '—'
      assert_select '.admin-action-progress-meter.is-indeterminate', count: 0
      assert_select '.admin-action-progress-meta', text: /#{Regexp.escape(I18n.t('admin.actions.progress.queued'))}/
      assert_select '.admin-action-progress-result', count: 0
    ensure
      RedisPool.get.del("admin:action_runs:#{run_id}") if run_id
    end

    test 'shows an indeterminate running state after the background job starts' do
      run_id = create_action_run
      Admin::ActionRun.start!(run_id)

      get admin_resource_action_run_url('albums', 'change_touhou_flag', run_id)

      assert_response :success
      assert_select '#admin-action-progress[data-status="processing"][data-polling="true"]'
      assert_select '#admin-action-progress h2', text: I18n.t('admin.actions.progress.statuses.processing')
      assert_select '.admin-action-progress-percent', text: '0%'
      assert_select '.admin-action-progress-meter.is-indeterminate', count: 1
      assert_select '.admin-action-progress-meter[aria-valuenow]', count: 0
      assert_select '.admin-action-progress-result', count: 0
    ensure
      RedisPool.get.del("admin:action_runs:#{run_id}") if run_id
    end

    private

    def create_action_run
      run_id = SecureRandom.uuid
      Admin::ActionRun.create!(
        run_id:,
        resource_key: 'albums',
        action_key: 'change_touhou_flag',
        action_label: '東方フラグを変更',
        redirect_path: '/admin/albums'
      )
      run_id
    end

    def with_action_run_method(method_name, replacement)
      original = Admin::ActionRun.method(method_name)
      Admin::ActionRun.define_singleton_method(method_name, replacement)
      yield
    ensure
      Admin::ActionRun.define_singleton_method(method_name, original)
    end
  end
end
