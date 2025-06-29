# frozen_string_literal: true

require 'date'

module AppleMusic
  autoload :Album,    'apple_music/album'
  autoload :Artist,   'apple_music/artist'
  autoload :Client,   'apple_music/client'
  autoload :Config,   'apple_music/config'
  autoload :Response, 'apple_music/response'
  autoload :Song,     'apple_music/song'
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
