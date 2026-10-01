# frozen_string_literal: true

require 'test_helper'
require 'open3'
require 'rbconfig'

class ProductionConfigurationTest < ActiveSupport::TestCase
  test 'production boot requires both admin credentials and APP_HOST' do
    base_env = {
      'RAILS_ENV' => 'production',
      'ADMIN_USERNAME' => 'admin',
      'ADMIN_PASSWORD' => 'secret',
      'APP_HOST' => 'example.test',
      'SECRET_KEY_BASE' => 'test-secret-key-base-for-production-boot-check'
    }

    [
      ['ADMIN_USERNAME', { 'ADMIN_USERNAME' => nil }],
      ['ADMIN_PASSWORD', { 'ADMIN_PASSWORD' => nil }],
      ['APP_HOST', { 'APP_HOST' => nil }]
    ].each do |missing_key, overrides|
      output, status = boot_production(base_env.merge(overrides))

      assert_not status.success?, "production boot unexpectedly succeeded without #{missing_key}: #{output}"
      assert_includes output, missing_key
    end
  end

  private

  def boot_production(env)
    Open3.capture2e(
      env.merge('RAILS_MASTER_KEY' => nil),
      RbConfig.ruby,
      '-r',
      Rails.root.join('config/environment.rb').to_s,
      '-e',
      'exit 0',
      chdir: Rails.root.to_s
    )
  end
end
