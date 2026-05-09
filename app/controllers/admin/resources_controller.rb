# frozen_string_literal: true

module Admin
  class ResourcesController < BaseController
    before_action :authenticate_admin_if_configured
    before_action :set_resource_config
    before_action :set_record, only: %i[show edit update destroy]

    def index
      scope = @resource_config.apply_to(@resource_config.model_class.all)
      scope = @resource_config.search(scope, params[:q].to_s.strip)
      @active_filters = @resource_config.normalize_filters(params.fetch(:filters, {}))
      @filters = @resource_config.filters
      scope = @resource_config.filter(scope, @active_filters)
      scope = @resource_config.sort(scope, params[:sort], params[:direction])
      @pagy, @records = pagy(scope, items: Admin::Resource::DEFAULT_ITEMS)
    end

    def show; end

    def new
      @record = @resource_config.model_class.new
    end

    def edit; end

    def create
      @record = @resource_config.model_class.new
      return render :new, status: :unprocessable_content unless assign_resource_params

      if @record.save
        redirect_to admin_resource_path(@resource_config.key, @record), notice: "#{@resource_config.label}を作成しました。"
      else
        render :new, status: :unprocessable_content
      end
    end

    def update
      return render :edit, status: :unprocessable_content unless assign_resource_params

      if @record.save
        redirect_to admin_resource_path(@resource_config.key, @record), notice: "#{@resource_config.label}を更新しました。"
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @record.destroy!
      redirect_to admin_resources_path(@resource_config.key), notice: "#{@resource_config.label}を削除しました。"
    rescue ActiveRecord::InvalidForeignKey, ActiveRecord::DeleteRestrictionError => e
      redirect_to admin_resource_path(@resource_config.key, @record), alert: "関連データがあるため削除できません: #{e.message}"
    end

    private

    def set_resource_config
      @resource_config = Admin::Resource.find!(params[:resource])
    end

    def set_record
      @record = @resource_config.model_class.find(params[:id])
    end

    def assign_resource_params
      @record.assign_attributes(permitted_resource_params)
      true
    rescue JSON::ParserError => e
      @record.errors.add(:base, "JSONの形式が正しくありません: #{e.message}")
      false
    end

    def permitted_resource_params
      attributes = params.expect(record: [*@resource_config.attributes_for_form]).to_h

      @resource_config.attributes_for_form.each do |attribute|
        next unless @resource_config.json_attribute?(attribute)
        next if attributes[attribute].blank?

        attributes[attribute] = JSON.parse(attributes[attribute])
      end

      attributes.except!(*@resource_config.readonly_attributes_for_update) if @record.persisted?

      attributes
    end
  end
end
