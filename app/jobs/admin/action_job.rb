# frozen_string_literal: true

require 'fileutils'

module Admin
  class ActionJob < ApplicationJob
    queue_as :admin_actions
    limits_concurrency(
      key: lambda do |job_args|
        job_args.values_at(:resource_key, :action_key, :record_id).compact.join(':')
      end,
      duration: Admin::ActionRun::TTL
    )

    def perform(run_id:, resource_key:, action_key:, fields:, record_id: nil)
      Admin::ActionRun.start!(run_id)
      progress = Admin::ActionProgress.new(run_id)
      ParallelRunner.with_forking_disabled do
        Admin::ActionProgress.with(progress) do
          resource_config = Admin::Resource.find!(resource_key)
          action = resource_config.action_for!(action_key)
          record = resource_config.model_class.find(record_id) if record_id.present?
          result = run_action(action, fields: deserialize_fields(fields), record:, run_id:)
          Admin::ActionRun.complete!(run_id, result)
        end
      end
    rescue StandardError => e
      Rails.logger.error("[Admin::ActionJob] #{action_key} failed: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace.join("\n")) if e.backtrace.present?
      Admin::ActionRun.fail!(run_id, e)
    ensure
      cleanup_uploaded_files(run_id)
    end

    private

    def deserialize_fields(fields)
      fields.to_h.transform_values { |value| deserialize_field_value(value) }
    end

    def run_action(action, fields:, record:, run_id:)
      arguments = { fields:, record: }
      run_parameters = action.method(:run).parameters
      arguments[:action_run_id] = run_id if run_parameters.any? { |type, name| type == :keyrest || (type == :key && name == :action_run_id) }

      action.run(**arguments)
    end

    def deserialize_field_value(value)
      return Admin::ActionUploadedFile.from_h(value) if uploaded_file_argument?(value)

      value
    end

    def uploaded_file_argument?(value)
      value.is_a?(Hash) && value[Admin::ActionUploadedFile::ACTION_UPLOADED_FILE_MARKER]
    end

    def cleanup_uploaded_files(run_id)
      FileUtils.rm_rf(Rails.root.join('tmp/admin_action_uploads', run_id))
    end
  end
end
