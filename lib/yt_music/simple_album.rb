# frozen_string_literal: true

module YtMusic
  class SimpleAlbum
    attr_reader :browse_id, :title, :url, :artists, :type, :year

    def initialize(item)
      @browse_id = item.dig('navigationEndpoint', 'browseEndpoint', 'browseId')
      @title = item.dig('flexColumns', 0, 'musicResponsiveListItemFlexColumnRenderer', 'text', 'runs', 0, 'text')
      @url = "https://music.youtube.com/browse/#{@browse_id}" if @browse_id
      contents = item.dig('flexColumns', 1, 'musicResponsiveListItemFlexColumnRenderer', 'text', 'runs')
      @type = contents&.shift&.dig('text')
      @year = extract_year_from_contents(contents)
      artist_contents = contents&.filter { _1['text'] != ' • ' }&.filter { _1['text'] != '、' }
      @artists = artist_contents.map { Artist.new _1 }
      super()
    end

    private

    def extract_year_from_contents(contents)
      return nil unless contents

      last_element = contents.pop
      return nil unless last_element

      text = last_element['text']
      return nil unless text

      text.to_i.to_s
    end
  end
end
