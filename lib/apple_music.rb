# frozen_string_literal: true

require 'date'
require_relative 'apple_music/config'
require_relative 'apple_music/connection'
require_relative 'apple_music/response'
require_relative 'apple_music/album'
require_relative 'apple_music/artist'
require_relative 'apple_music/song'

module AppleMusic
  class << self
    attr_writer :config

    def config
      @config ||= Config.new
    end

    def configure
      yield(config)
    end
  end

end