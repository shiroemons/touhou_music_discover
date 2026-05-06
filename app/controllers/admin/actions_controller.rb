# frozen_string_literal: true

require 'fileutils'

module Admin
  class ActionsController < BaseController
    before_action :authenticate_admin_if_configured
    before_action :set_resource_config
    before_action :set_record
    before_action :set_action
    helper_method :action_run_progress_path

    def show
      load_action_run
    end

    def new; end

    def create
      run_id = SecureRandom.uuid
      fields = prepare_action_fields(run_id)
      Admin::ActionRun.create!(
        run_id:,
        resource_key: @resource_config.key,
        action_key: @action.key,
        action_label: @action.label,
        redirect_path:
      )
      start_action_thread(run_id:, fields:)

      redirect_to action_run_path(run_id)
    end

    def progress
      load_action_run

      respond_to do |format|
        format.turbo_stream
      end
    end

    private

    def set_resource_config
      @resource_config = Admin::Resource.find!(params[:resource])
    end

    def set_action
      @action = @resource_config.action_for!(params[:action_key])
      raise ActiveRecord::RecordNotFound, "Action is not available for collection: #{@action.key}" if @record_id.blank? && @action.member?
    end

    def set_record
      @record_id = params[:id]
      @record = @resource_config.model_class.find(@record_id) if @record_id.present?
    end

    def action_fields
      return {} if params[:fields].blank?

      params.expect(fields: [*@action.fields.map(&:name)]).to_h
    end

    def prepare_action_fields(run_id)
      action_fields.transform_values.with_index do |value, index|
        value.respond_to?(:tempfile) ? persist_uploaded_file(run_id, index, value) : value
      end
    end

    def persist_uploaded_file(run_id, index, uploaded_file)
      upload_dir = Rails.root.join('tmp/admin_action_uploads', run_id)
      FileUtils.mkdir_p(upload_dir)
      extension = File.extname(uploaded_file.original_filename.to_s)
      path = upload_dir.join("#{index}#{extension}")
      FileUtils.cp(uploaded_file.tempfile.path, path)
      Admin::ActionUploadedFile.new(
        path: path.to_s,
        content_type: uploaded_file.content_type,
        original_filename: uploaded_file.original_filename
      )
    end

    def start_action_thread(run_id:, fields:)
      resource_key = @resource_config.key
      action_key = @action.key
      record_id = @record_id

      Thread.new do
        Rails.application.executor.wrap do
          progress = Admin::ActionProgress.new(run_id)
          Admin::ActionProgress.with(progress) do
            resource_config = Admin::Resource.find!(resource_key)
            action = resource_config.action_for!(action_key)
            record = resource_config.model_class.find(record_id) if record_id.present?
            result = action.run(fields:, record:)
            Admin::ActionRun.complete!(run_id, result)
          end
        rescue StandardError => e
          Rails.logger.error("[Admin::ActionsController] #{action_key} failed in background: #{e.class} - #{e.message}")
          Rails.logger.error(e.backtrace.join("\n")) if e.backtrace.present?
          Admin::ActionRun.fail!(run_id, e)
        ensure
          cleanup_uploaded_files(run_id)
          ActiveRecord::Base.connection_pool.release_connection
        end
      end
    end

    def cleanup_uploaded_files(run_id)
      FileUtils.rm_rf(Rails.root.join('tmp/admin_action_uploads', run_id))
    end

    def load_action_run
      @action_run = Admin::ActionRun.find!(params[:run_id])
    rescue Admin::ActionRun::NotFound
      raise ActiveRecord::RecordNotFound, "Unknown admin action run: #{params[:run_id]}"
    end

    def redirect_path
      return admin_resource_path(@resource_config.key, @record) if @record.present?

      admin_resources_path(@resource_config.key)
    end

    def action_run_path(run_id)
      return admin_member_resource_action_run_path(@resource_config.key, @record, @action.key, run_id) if @record.present?

      admin_resource_action_run_path(@resource_config.key, @action.key, run_id)
    end

    def action_run_progress_path(run_id)
      return admin_member_resource_action_run_progress_path(@resource_config.key, @record, @action.key, run_id) if @record.present?

      admin_resource_action_run_progress_path(@resource_config.key, @action.key, run_id)
    end
  end
end
