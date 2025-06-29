# frozen_string_literal: true

require 'date'

require_relative 'line_music/client'

module LineMusic
  autoload :Album,  'line_music/album'
  autoload :Artist, 'line_music/artist'
  autoload :Base,   'line_music/base'
  autoload :Client, 'line_music/client'
  autoload :Track,  'line_music/track'
end
