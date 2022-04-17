# frozen_string_literal: true

module YTMusic
  class SimpleAlbum
    attr_reader :browse_id, :title, :url, :artists, :type, :year

    def initialize(item)
      @browse_id = item.dig('navigationEndpoint', 'browseEndpoint', 'browseId')
      @title = item.dig('flexColumns', 0, 'musicResponsiveListItemFlexColumnRenderer', 'text', 'runs', 0, 'text')
      @url = "https://music.youtube.com/browse/#{@browse_id}" if @browse_id
      contents = item.dig('flexColumns', 1, 'musicResponsiveListItemFlexColumnRenderer', 'text', 'runs')
      @type = contents&.shift&.dig('text')
      @year = contents&.pop&.dig('text')
      artist_contents = contents&.filter { _1['text'] != ' • ' }&.filter { _1['text'] != '、' }
      @artists = artist_contents.map { Artist.new _1 }
      super()
    end
  end
end
