# frozen_string_literal: true

module YtMusic
  autoload :Album,       'yt_music/album'
  autoload :Artist,      'yt_music/artist'
  autoload :Base,        'yt_music/base'
  autoload :Client,      'yt_music/client'
  autoload :Response,    'yt_music/response'
  autoload :SimpleAlbum, 'yt_music/simple_album'
  autoload :Thumbnail,   'yt_music/thumbnail'
  autoload :Track,       'yt_music/track'

  # Client メソッドの委譲
  class << self
    def generate_body(options = {})
      Client.generate_body(options)
    end

    def send_request(endpoint, body: nil, options: {})
      Client.send_request(endpoint, body: body, options: options)
    end
  end
end
