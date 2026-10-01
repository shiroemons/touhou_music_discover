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
      assert_includes output, '-e development'
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

    test 'rejects all arguments passed to the wrapper' do
      cases = {
        'separate -b' => ['-b', '0.0.0.0'],
        '--binding=0.0.0.0' => ['--binding=0.0.0.0'],
        'concatenated -b value' => ['-b0.0.0.0'],
        'bundled -Cb' => ['-Cb', '0.0.0.0'],
        'bundled -db' => ['-db'],
        '--no-binding' => ['--no-binding'],
        '--skip-binding' => ['--skip-binding'],
        '--no_binding' => ['--no_binding'],
        '--skip_binding' => ['--skip_binding'],
        'separate -e' => ['-e', 'production'],
        'after --' => ['--', '-b', '0.0.0.0'],
        'port option' => ['-p', '3000'],
        'help option' => ['--help'],
        'bare --' => ['--']
      }
      results = cases.transform_values { |server_args| run_dev_server(server_args: server_args) }
      rejected_cases = results.filter_map { |description, (_, status)| description if status.exitstatus == 1 }

      assert_equal cases.keys, rejected_cases

      results.each do |description, (output, _status)|
        assert_includes output, 'RAILS_BIND_ADDRESS', description
        assert_includes output, 'RAILS_ENV', description
        assert_includes output, 'PORT', description
        assert_not_includes output, 'bin/rails', description
      end
    end

    test 'uses RACK_ENV when RAILS_ENV is unset' do
      output, status = run_dev_server(
        { 'RAILS_BIND_ADDRESS' => '0.0.0.0', 'RAILS_ENV' => nil, 'RACK_ENV' => 'production' }
      )

      assert_equal 1, status.exitstatus
      assert_includes output, '開発環境でのみ許可'
    end

    test 'prefers RAILS_ENV and passes it to Rails explicitly' do
      output, status = run_dev_server(
        { 'RAILS_BIND_ADDRESS' => '0.0.0.0', 'RAILS_ENV' => 'development', 'RACK_ENV' => 'production' }
      )

      assert_predicate status, :success?
      assert_includes output, '-e development'
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

      output, status = run_dev_server(
        docker_compose.dig('services', 'web', 'environment').slice(
          'RAILS_ENV', 'RAILS_BIND_ADDRESS', 'PORT', 'RAILS_PORT_FIXED'
        ),
        # 共有の開発サーバーが 3000 番を使用中でも、Docker の起動引数を検証できるようにする。
        port_available: true
      )

      assert_predicate status, :success?, output
      assert_equal "bin/rails server -b 0.0.0.0 -p 3000 -e development\n", output
    end

    private

    def run_dev_server(overrides = {}, server_args: [], port_available: false)
      wrapper = <<~RUBY
        require #{Rails.root.join('lib/development/port_selector').to_s.inspect}
        Development::PortSelector.define_method(:port_available?) { |_port| true } if #{port_available}
        module Kernel
          def exec(*args)
            puts args.join(' ')
          end
        end
        load ARGV.shift
      RUBY

      Dir.mktmpdir do |directory|
        Open3.capture2e(
          {
            'PORT' => '0', 'RAILS_ENV' => nil, 'RACK_ENV' => nil,
            'RAILS_BIND_ADDRESS' => nil, 'RAILS_PORT_FIXED' => nil
          }.merge(overrides),
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
