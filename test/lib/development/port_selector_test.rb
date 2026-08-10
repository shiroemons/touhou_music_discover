# frozen_string_literal: true

require 'test_helper'
require_relative '../../../lib/development/port_selector'

module Development
  class PortSelectorTest < ActiveSupport::TestCase
    test 'preferred port is selected when it is available' do
      available_ports = ->(port) { port == 3000 }

      assert_equal 3000, PortSelector.select(preferred_port: 3000, port_available: available_ports)
    end

    test 'selects the next available port when the preferred port is occupied' do
      available_ports = ->(port) { port >= 3001 }

      assert_equal 3001, PortSelector.select(preferred_port: 3000, port_available: available_ports)
    end

    test 'raises a clear error when the preferred port is invalid' do
      error = assert_raises(PortSelector::InvalidPort) do
        PortSelector.select(preferred_port: 'not-a-port')
      end

      assert_match(/preferred port/, error.message)
    end

    test 'raises when no port in the search range is available' do
      error = assert_raises(PortSelector::NoAvailablePort) do
        PortSelector.select(preferred_port: 3000, max_port: 3002, port_available: ->(_port) { false })
      end

      assert_match(/3000 through 3002/, error.message)
    end
  end
end
