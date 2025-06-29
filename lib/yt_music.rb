# frozen_string_literal: true

require_relative 'yt_music/connection'

module YTMusic
  autoload :Album,       'yt_music/album'
  autoload :Artist,      'yt_music/artist'
  autoload :Base,        'yt_music/base'
  autoload :Response,    'yt_music/response'
  autoload :SimpleAlbum, 'yt_music/simple_album'
  autoload :Thumbnail,   'yt_music/thumbnail'
  autoload :Track,       'yt_music/track'
end
