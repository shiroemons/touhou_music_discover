# frozen_string_literal: true

module YtMusic
  class Artist < Base
    attr_reader :name, :browse_id, :url

    def initialize(content)
      @name = content['text']
      browse_id = content.dig('navigationEndpoint', 'browseEndpoint', 'browseId')
      @browse_id = browse_id if browse_id
      @url = "https://music.youtube.com/channel/#{browse_id}" if browse_id
      super()
    end
  end
end
