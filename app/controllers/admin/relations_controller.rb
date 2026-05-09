# frozen_string_literal: true

module Admin
  class RelationsController < BaseController
    before_action :authenticate_admin_if_configured
    before_action :set_resource_config
    before_action :set_record
    before_action :set_relation_section

    def create
      related_record = find_related_record!(params[:related_query].to_s.strip)
      collection = @record.public_send(@relation_section.name)

      collection << related_record unless collection.exists?(related_record.id)

      redirect_to admin_resource_path(@resource_config.key, @record), notice: t('admin.relations.create_success')
    rescue ActiveRecord::RecordNotFound => e
      redirect_to admin_resource_path(@resource_config.key, @record), alert: t('admin.relations.record_not_found', message: e.message)
    end

    def destroy
      related_record = @relation_section.reflection.klass.find(params[:related_id])

      @record.public_send(@relation_section.name).delete(related_record)
      redirect_to admin_resource_path(@resource_config.key, @record), notice: t('admin.relations.destroy_success')
    end

    private

    def set_resource_config
      @resource_config = Admin::Resource.find!(params[:resource])
    end

    def set_record
      @record = @resource_config.model_class.find(params[:id])
    end

    def set_relation_section
      reflection = @resource_config.model_class.reflect_on_association(params[:association].to_sym)
      raise ActiveRecord::RecordNotFound, "Unknown relation: #{params[:association]}" if reflection.blank?

      @relation_section = Admin::RelationSection.new(resource_config: @resource_config, record: @record, reflection:)
      raise ActiveRecord::RecordNotFound, "Relation is not editable: #{params[:association]}" unless @relation_section.editable?
    end

    def find_related_record!(query)
      raise ActiveRecord::RecordNotFound, t('admin.relations.blank_query') if query.blank?

      related_resource = @relation_section.associated_resource
      related_class = @relation_section.reflection.klass
      primary_key = related_class.primary_key

      related_class.find_by(primary_key => query) ||
        related_resource.search(related_resource.apply_to(related_class.all), query).first ||
        raise(ActiveRecord::RecordNotFound, query)
    end
  end
end
