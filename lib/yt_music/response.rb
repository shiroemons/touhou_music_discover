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
      raise ArgumentError, "YouTube Music response must be a Hash, got #{response.class}" unless response.is_a?(Hash)

      contents = response.dig('contents', 'tabbedSearchResultsRenderer', 'tabs', 0, 'tabRenderer', 'content', 'sectionListRenderer', 'contents')
      return result if contents.blank?

      contents.each do |content|
        ctx = content['musicShelfRenderer']
        next if ctx.blank?

        category = ctx.dig('title', 'runs', 0, 'text')
        case category
        when 'アルバム', 'Albums'
          result[:albums] = Array(ctx['contents']).filter_map do |item|
            renderer = item['musicResponsiveListItemRenderer']
            SimpleAlbum.new(renderer) if renderer
          end
        when '曲', 'Songs'
          result[:songs] = Array(ctx['contents']).filter_map do |item|
            renderer = item['musicResponsiveListItemRenderer']
            SimpleSong.new(renderer) if renderer
          end
        end
      end
      result
    end
  end
end
