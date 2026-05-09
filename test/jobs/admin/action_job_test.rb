# frozen_string_literal: true

require 'test_helper'

module Admin
  class ActionJobTest < ActiveJob::TestCase
    test 'runs admin action and completes action run' do
      result = Admin::ActionResult.new(status: :success, message: 'done')
      action = FakeAction.new(result)
      resource = FakeResource.new(action)
      completed = nil

      with_admin_resource(resource) do
        with_action_run_method(:complete!, ->(run_id, action_result) { completed = [run_id, action_result] }) do
          Admin::ActionJob.perform_now(
            run_id: 'run-1',
            resource_key: 'albums',
            action_key: 'fake_action',
            fields: { 'name' => 'value' }
          )
        end
      end

      assert_equal [{ fields: { 'name' => 'value' }, record: nil }], action.calls
      assert_equal ['run-1', result], completed
    end

    test 'deserializes uploaded file fields before running admin action' do
      result = Admin::ActionResult.new(status: :success, message: 'done')
      action = FakeAction.new(result)
      resource = FakeResource.new(action)
      uploaded_file = Admin::ActionUploadedFile.new(
        path: Rails.root.join('tmp/test.tsv').to_s,
        content_type: 'text/tab-separated-values',
        original_filename: 'test.tsv'
      )

      with_admin_resource(resource) do
        with_action_run_method(:complete!, ->(_run_id, _action_result) {}) do
          Admin::ActionJob.perform_now(
            run_id: 'run-1',
            resource_key: 'tracks',
            action_key: 'import_tracks_with_original_songs',
            fields: { 'tsv_file' => uploaded_file.as_job_argument }
          )
        end
      end

      actual_file = action.calls.first.fetch(:fields).fetch('tsv_file')
      assert_instance_of Admin::ActionUploadedFile, actual_file
      assert_equal uploaded_file.path, actual_file.path
      assert_equal uploaded_file.content_type, actual_file.content_type
      assert_equal uploaded_file.original_filename, actual_file.original_filename
    end

    FakeResource = Data.define(:action) do
      def action_for!(_action_key)
        action
      end
    end

    private

    class FakeAction
      attr_reader :calls

      def initialize(result)
        @result = result
        @calls = []
      end

      def run(fields:, record: nil)
        @calls << { fields:, record: }
        @result
      end
    end

    def with_admin_resource(resource)
      original = Admin::Resource.method(:find!)
      Admin::Resource.define_singleton_method(:find!, ->(_resource_key) { resource })
      yield
    ensure
      Admin::Resource.define_singleton_method(:find!, original)
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
