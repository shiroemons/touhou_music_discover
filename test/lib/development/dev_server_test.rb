# frozen_string_literal: true

require 'test_helper'
require 'open3'
require 'rbconfig'
require 'socket'
require 'tmpdir'
require 'yaml'

module Development
  class DevServerTest < ActiveSupport::TestCase
    test 'defaults to loopback binding' do
      output, status = run_dev_server

      assert_predicate status, :success?
      assert_includes output, '-b 127.0.0.1'
    end

    test 'rejects public binding outside development' do
      output, status = run_dev_server({ 'RAILS_BIND_ADDRESS' => '0.0.0.0', 'RAILS_ENV' => 'production' })

      assert_equal 1, status.exitstatus
      assert_includes output, '開発環境でのみ許可'
    end

    test 'rejects IPv6 wildcard binding outside development' do
      output, status = run_dev_server({ 'RAILS_BIND_ADDRESS' => '::', 'RAILS_ENV' => 'production' })

      assert_equal 1, status.exitstatus
      assert_includes output, '開発環境でのみ許可'
    end

    test 'rejects public binding when production is selected by Rails arguments' do
      output, status = run_dev_server(
        { 'RAILS_BIND_ADDRESS' => '0.0.0.0', 'RAILS_ENV' => nil },
        server_args: ['-e', 'production']
      )

      assert_equal 1, status.exitstatus
      assert_includes output, '開発環境でのみ許可'
    end

    test 'allows explicit public binding in development' do
      output, status = run_dev_server({ 'RAILS_BIND_ADDRESS' => '0.0.0.0', 'RAILS_ENV' => 'development' })

      assert_predicate status, :success?
      assert_includes output, '-b 0.0.0.0'
    end

    test 'does not select another port when the configured port is fixed' do
      listener = TCPServer.new('0.0.0.0', 0)
      port = listener.addr[1].to_s
      output, status = run_dev_server({ 'PORT' => port, 'RAILS_PORT_FIXED' => 'true' })

      assert_equal 1, status.exitstatus
      assert_includes output, "no available TCP port from #{port} through #{port}"
    ensure
      listener&.close
    end

    test 'compose services allow explicitly enabling admin authentication' do
      process_compose = YAML.safe_load_file(Rails.root.join('process-compose.yaml'))
      docker_compose = YAML.safe_load_file(Rails.root.join('docker-compose.yml'))

      assert_includes process_compose.dig('processes', 'rails', 'environment'),
                      'ADMIN_AUTH_DISABLED=${ADMIN_AUTH_DISABLED:-true}'
      assert_equal '${ADMIN_AUTH_DISABLED:-true}',
                   docker_compose.dig('services', 'web', 'environment', 'ADMIN_AUTH_DISABLED')
    end

    test 'Docker pins the Rails port to the published port' do
      docker_compose = YAML.safe_load_file(Rails.root.join('docker-compose.yml'))

      assert_equal '3000', docker_compose.dig('services', 'web', 'environment', 'PORT')
      assert_equal 'true', docker_compose.dig('services', 'web', 'environment', 'RAILS_PORT_FIXED')
      assert_equal ['3000:3000'], docker_compose.dig('services', 'web', 'ports')
    end

    private

    def run_dev_server(overrides = {}, server_args: [])
      wrapper = <<~RUBY
        module Kernel
          def exec(*args)
            puts args.join(' ')
          end
        end
        load ARGV.shift
      RUBY

      Dir.mktmpdir do |directory|
        Open3.capture2e(
          { 'PORT' => '0' }.merge(overrides),
          RbConfig.ruby,
          '-e',
          wrapper,
          Rails.root.join('bin/dev-server').to_s,
          *server_args,
          chdir: directory
        )
      end
    end
  end
end
