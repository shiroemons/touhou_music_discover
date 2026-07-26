# frozen_string_literal: true

module YtMusic
  class Response
    attr_reader :data

    def initialize(raw_response)
      @data = parser(raw_response)
    end

    private

    def parser(response)
      result = {}
      contents = response.dig('contents', 'tabbedSearchResultsRenderer', 'tabs', 0, 'tabRenderer', 'content', 'sectionListRenderer', 'contents')
      return result if contents.blank?

      contents.each do |content|
        ctx = content['musicShelfRenderer']
        next if ctx.blank?

        category = ctx.dig('title', 'runs', 0, 'text')
        case category
        when 'アルバム'
          result[:albums] = ctx['contents'].map { SimpleAlbum.new it['musicResponsiveListItemRenderer'] }
        end
      end
      result
    end
  end
end
