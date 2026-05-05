# frozen_string_literal: true

module Admin
  class DashboardController < BaseController
    before_action :authenticate_admin_if_configured

    def show
      @resources = admin_resources
      @resource_summaries = @resources.map { |resource| dashboard_summary(resource) }
      @total_records = @resource_summaries.sum { |summary| summary[:count] }
      @total_actions = @resource_summaries.sum { |summary| summary[:actions_count] }
      @top_resources = @resource_summaries.max_by(6) { |summary| summary[:count] }
      @recent_resources = @resource_summaries
                          .select { |summary| summary[:latest_updated_at].present? }
                          .sort_by { |summary| summary[:latest_updated_at] }
                          .reverse
                          .first(6)
      @summary_by_key = @resource_summaries.index_by { |summary| summary[:resource].key }
      @resource_groups = admin_resource_groups
    end

    private

    def dashboard_summary(resource)
      {
        resource:,
        count: resource.count,
        actions_count: resource.actions.count,
        latest_updated_at: latest_updated_at(resource)
      }
    end

    def latest_updated_at(resource)
      return unless resource.model_class.column_names.include?('updated_at')

      resource.model_class.maximum(:updated_at)
    end
  end
end
