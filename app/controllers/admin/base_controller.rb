# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    include Pagy::Backend

    layout 'admin'
    around_action :switch_admin_locale

    helper_method :admin_resources

    private

    def switch_admin_locale(&)
      I18n.with_locale(:ja, &)
    end

    def admin_resources
      Admin::Resource.all
    end

    def authenticate_admin_if_configured
      username = ENV.fetch('ADMIN_USERNAME', nil)
      password = ENV.fetch('ADMIN_PASSWORD', nil)
      return if username.blank? || password.blank?

      authenticate_or_request_with_http_basic('Admin') do |provided_username, provided_password|
        ActiveSupport::SecurityUtils.secure_compare(provided_username, username) &
          ActiveSupport::SecurityUtils.secure_compare(provided_password, password)
      end
    end
  end
end
