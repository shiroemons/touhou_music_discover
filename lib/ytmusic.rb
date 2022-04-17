# frozen_string_literal: true

require_relative 'ytmusic/connection'

module YTMusic
  autoload :Album,       'ytmusic/album'
  autoload :Artist,      'ytmusic/artist'
  autoload :Base,        'ytmusic/base'
  autoload :Response,    'ytmusic/response'
  autoload :SimpleAlbum, 'ytmusic/simple_album'
  autoload :Thumbnail,   'ytmusic/thumbnail'
  autoload :Track,       'ytmusic/track'
end
