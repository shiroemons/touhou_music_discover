# frozen_string_literal: true

module Admin
  class DashboardController < BaseController
    before_action :authenticate_admin_if_configured

    def show
      @resources = admin_resources
      @resource_summaries = @resources.map { |resource| dashboard_summary(resource) }
      @dashboard_metrics = Admin::DashboardMetrics.call
      @summary_by_key = @resource_summaries.index_by { |summary| summary[:resource].key }
      @resource_groups = admin_resource_groups
    end

    private

    def dashboard_summary(resource)
      {
        resource:,
        count: resource.count
      }
    end
  end
end
