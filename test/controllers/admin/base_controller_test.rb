# frozen_string_literal: true

require 'test_helper'

module Admin
  class BaseControllerTest < ActionDispatch::IntegrationTest
    test 'requires both admin credentials and accepts matching credentials' do
      with_admin_auth_settings('ADMIN_USERNAME' => 'admin', 'ADMIN_PASSWORD' => 'secret') do
        get admin_root_url

        assert_response :unauthorized

        get admin_root_url, headers: basic_auth_headers('admin', 'secret')

        assert_response :success
      end
    end

    test 'rejects authentication when either credential is missing' do
      [
        { 'ADMIN_USERNAME' => nil, 'ADMIN_PASSWORD' => 'secret' },
        { 'ADMIN_USERNAME' => 'admin', 'ADMIN_PASSWORD' => nil }
      ].each do |credentials|
        with_admin_auth_settings(credentials) do
          get admin_root_url, headers: basic_auth_headers('admin', 'secret')

          assert_response :unauthorized
        end
      end
    end

    private

    def with_admin_auth_settings(overrides)
      previous_env = overrides.to_h { |key, _value| [key, ENV.fetch(key, nil)] }
      previous_auth_disabled = Rails.application.config.x.admin_auth_disabled
      overrides.each { |key, value| ENV[key] = value }
      Rails.application.config.x.admin_auth_disabled = false

      yield
    ensure
      previous_env&.each { |key, value| ENV[key] = value }
      Rails.application.config.x.admin_auth_disabled = previous_auth_disabled
    end

    def basic_auth_headers(username, password)
      { 'Authorization' => ActionController::HttpAuthentication::Basic.encode_credentials(username, password) }
    end
  end
end
