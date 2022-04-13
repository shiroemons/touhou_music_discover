# frozen_string_literal: true

require 'date'

require_relative 'line_music/connection'

module LineMusic
  autoload :Album,  'line_music/album'
  autoload :Artist, 'line_music/artist'
  autoload :Base,   'line_music/base'
  autoload :Track,  'line_music/track'
end
