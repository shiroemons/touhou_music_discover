# frozen_string_literal: true

module Admin
  class DashboardController < BaseController
    before_action :authenticate_admin_if_configured

    def show
      @resources = admin_resources
    end
  end
end
