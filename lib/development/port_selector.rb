# frozen_string_literal: true

require 'socket'

module Development
  class PortSelector
    DEFAULT_PORT = 3000
    MIN_PORT = 1
    MAX_PORT = 65_535

    class InvalidPort < ArgumentError; end
    class NoAvailablePort < StandardError; end

    def self.select(preferred_port:, max_port: MAX_PORT, port_available: nil)
      new(preferred_port:, max_port:, port_available:).select
    end

    def initialize(preferred_port:, max_port:, port_available: nil)
      @preferred_port = parse_port(preferred_port, 'preferred port')
      @max_port = parse_port(max_port, 'maximum port')
      @port_available = port_available || method(:port_available?)

      return if @max_port >= @preferred_port

      raise InvalidPort, 'maximum port must be greater than or equal to preferred port'
    end

    def select
      available_port = (@preferred_port..@max_port).find { |port| @port_available.call(port) }
      return available_port if available_port

      raise NoAvailablePort, "no available TCP port from #{@preferred_port} through #{@max_port}"
    end

    private

    def parse_port(value, name)
      port = Integer(value.to_s, 10)
    rescue ArgumentError
      raise InvalidPort, "#{name} must be a number between #{MIN_PORT} and #{MAX_PORT}: #{value.inspect}"
    else
      return port if port.between?(MIN_PORT, MAX_PORT)

      raise InvalidPort, "#{name} must be between #{MIN_PORT} and #{MAX_PORT}: #{value.inspect}"
    end

    def port_available?(port)
      socket = TCPServer.new('0.0.0.0', port)
      socket.close
      true
    # macOS can report EPERM instead of EADDRINUSE when another process owns
    # the port but its socket details are not accessible to the current user.
    rescue Errno::EADDRINUSE, Errno::EACCES, Errno::EPERM
      false
    end
  end
end
