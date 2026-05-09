# frozen_string_literal: true

require 'fileutils'

module Admin
  class ActionJob < ApplicationJob
    queue_as :admin_actions

    def perform(run_id:, resource_key:, action_key:, fields:, record_id: nil)
      progress = Admin::ActionProgress.new(run_id)
      Admin::ActionProgress.with(progress) do
        resource_config = Admin::Resource.find!(resource_key)
        action = resource_config.action_for!(action_key)
        record = resource_config.model_class.find(record_id) if record_id.present?
        result = action.run(fields: deserialize_fields(fields), record:)
        Admin::ActionRun.complete!(run_id, result)
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

    def deserialize_field_value(value)
      return Admin::ActionUploadedFile.from_h(value) if uploaded_file_argument?(value)

      value
    end

    def uploaded_file_argument?(value)
      value.is_a?(Hash) && value[Admin::ACTION_UPLOADED_FILE_MARKER]
    end

    def cleanup_uploaded_files(run_id)
      FileUtils.rm_rf(Rails.root.join('tmp/admin_action_uploads', run_id))
    end
  end
end
