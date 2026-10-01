# frozen_string_literal: true

require 'test_helper'
require 'open3'
require 'rbconfig'
require 'tmpdir'

module Development
  class DevServerTest < ActiveSupport::TestCase
    test 'defaults to loopback binding' do
      output, status = run_dev_server

      assert_predicate status, :success?
      assert_includes output, '-b 127.0.0.1'
    end

    test 'rejects public binding outside development' do
      output, status = run_dev_server('RAILS_BIND_ADDRESS' => '0.0.0.0', 'RAILS_ENV' => 'production')

      assert_equal 1, status.exitstatus
      assert_includes output, '開発環境でのみ許可'
    end

    test 'allows explicit public binding in development' do
      output, status = run_dev_server('RAILS_BIND_ADDRESS' => '0.0.0.0', 'RAILS_ENV' => 'development')

      assert_predicate status, :success?
      assert_includes output, '-b 0.0.0.0'
    end

    private

    def run_dev_server(overrides = {})
      wrapper = <<~RUBY
        module Kernel
          def exec(*args)
            puts args.join(' ')
          end
        end
        load ARGV.fetch(0)
      RUBY

      Dir.mktmpdir do |directory|
        Open3.capture2e(
          { 'PORT' => '0' }.merge(overrides),
          RbConfig.ruby,
          '-e',
          wrapper,
          Rails.root.join('bin/dev-server').to_s,
          chdir: directory
        )
      end
    end
  end
end
