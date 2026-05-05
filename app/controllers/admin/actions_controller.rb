# frozen_string_literal: true

module Admin
  class ActionsController < BaseController
    before_action :authenticate_admin_if_configured
    before_action :set_resource_config
    before_action :set_record
    before_action :set_action

    def new; end

    def create
      result = @action.run(fields: action_fields, record: @record)
      redirect_to redirect_path, flash: flash_for(result)
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

    def redirect_path
      return admin_resource_path(@resource_config.key, @record) if @record.present?

      admin_resources_path(@resource_config.key)
    end

    def flash_for(result)
      key = result.success? ? :notice : :alert
      { key => result.message }
    end
  end
end
