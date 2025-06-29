# frozen_string_literal: true

require 'date'

module LineMusic
  autoload :Album,  'line_music/album'
  autoload :Artist, 'line_music/artist'
  autoload :Base,   'line_music/base'
  autoload :Client, 'line_music/client'
  autoload :Track,  'line_music/track'

  # HTTPメソッドの委譲
  class << self
    def get(path, params = {})
      Client.client.get(path, params)
    end

    def post(path, body = {})
      Client.client.post(path, body)
    end

    def put(path, body = {})
      Client.client.put(path, body)
    end

    def delete(path)
      Client.client.delete(path)
    end
  end
end
