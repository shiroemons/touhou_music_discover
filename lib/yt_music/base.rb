# frozen_string_literal: true

module YtMusic
  class Base
    FILTERS = %w[albums artists playlists community_playlists featured_playlists songs videos].freeze

    class << self
      def find(id, _type = nil)
        body = YtMusic.generate_body({ id: })
        response = YtMusic.send_request('browse', body:)

        response.body
      end

      def search(query, filter)
        body = YtMusic.generate_body
        body['query'] = query

        raise "not support filter: #{filter}" if filter && FILTERS.exclude?(filter)

        body['params'] = search_params(filter:)

        response = YtMusic.send_request('search', body:)

        Response.new(response.body)
      end

      FILTERED_PARAM1 = 'EgWKAQI'

      private

      def search_params(filter:)
        params = nil
        return params if filter.nil?

        if filter
          param1 = FILTERED_PARAM1
          param2 = param2(filter)
          param3 = 'AWoKEAMQBBAJEAoQBQ%3D%3D'
        end

        params || "#{param1}#{param2}#{param3}"
      end

      def param2(filter)
        filter_params = { songs: 'I', videos: 'Q', albums: 'Y', artists: 'g', playlists: 'o' }
        filter_params[filter.to_sym]
      end
    end
  end
end
