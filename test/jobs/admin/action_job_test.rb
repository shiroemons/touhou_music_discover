# frozen_string_literal: true

require 'test_helper'

module Admin
  class ActionJobTest < ActiveJob::TestCase
    test 'runs admin action and completes action run' do
      result = Admin::ActionResult.new(status: :success, message: 'done')
      action = FakeAction.new(result)
      resource = FakeResource.new(action)
      completed = nil
      started_run_id = nil

      with_admin_resource(resource) do
        with_action_run_method(:start!, ->(run_id) { started_run_id = run_id }) do
          with_action_run_method(:complete!, ->(run_id, action_result) { completed = [run_id, action_result] }) do
            Admin::ActionJob.perform_now(
              run_id: 'run-1',
              resource_key: 'albums',
              action_key: 'fake_action',
              fields: { 'name' => 'value' }
            )
          end
        end
      end

      assert_equal 'run-1', started_run_id
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
        with_action_run_method(:start!, ->(_run_id) {}) do
          with_action_run_method(:complete!, ->(_run_id, _action_result) {}) do
            Admin::ActionJob.perform_now(
              run_id: 'run-1',
              resource_key: 'tracks',
              action_key: 'import_tracks_with_original_songs',
              fields: { 'tsv_file' => uploaded_file.as_job_argument }
            )
          end
        end
      end

      actual_file = action.calls.first.fetch(:fields).fetch('tsv_file')

      assert_instance_of Admin::ActionUploadedFile, actual_file
      assert_equal uploaded_file.path, actual_file.path
      assert_equal uploaded_file.content_type, actual_file.content_type
      assert_equal uploaded_file.original_filename, actual_file.original_filename
    end

    test 'limits concurrent executions of the same action and target' do
      first_job = build_job(action_key: 'fetch_albums')
      duplicate_job = build_job(action_key: 'fetch_albums')
      different_action_job = build_job(action_key: 'fetch_tracks')
      different_record_job = build_job(action_key: 'fetch_albums', record_id: 'record-2')

      assert_predicate first_job, :concurrency_limited?
      assert_equal 1, first_job.class.concurrency_limit
      assert_equal Admin::ActionRun::TTL, first_job.class.concurrency_duration
      assert_equal first_job.concurrency_key, duplicate_job.concurrency_key
      assert_not_equal first_job.concurrency_key, different_action_job.concurrency_key
      assert_not_equal first_job.concurrency_key, different_record_job.concurrency_key
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

    def build_job(action_key:, record_id: nil)
      Admin::ActionJob.new(
        run_id: SecureRandom.uuid,
        resource_key: 'albums',
        action_key:,
        fields: {},
        record_id:
      )
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
