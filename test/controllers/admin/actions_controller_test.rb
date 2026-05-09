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

    private

    def with_action_run_method(method_name, replacement)
      original = Admin::ActionRun.method(method_name)
      Admin::ActionRun.define_singleton_method(method_name, replacement)
      yield
    ensure
      Admin::ActionRun.define_singleton_method(method_name, original)
    end
  end
end
