# frozen_string_literal: true

module YTMusic
  class Album < Base
    class << self
      def find(id)
        response = super(id, 'album')
        Album.new response
      end

      def search(query)
        super(query, 'albums')
      end
    end

    attr_reader :id, :title, :url, :artists, :type, :year,
                :track_total_count, :playlist_url, :tracks, :thumbnails,
                :duration_text, :duration_seconds

    def initialize(response)
      @title = response.dig('header', 'musicDetailHeaderRenderer', 'title', 'runs', 0, 'text')
      contents = response.dig('header', 'musicDetailHeaderRenderer', 'subtitle', 'runs')
      @type = contents&.shift&.dig('text')
      @year = contents&.pop&.dig('text')
      artist_contents = contents&.filter { _1['text'] != ' • ' }&.filter { _1['text'] != '、' }
      @artists = artist_contents.map { Artist.new _1 }

      @track_total_count = response.dig('header', 'musicDetailHeaderRenderer', 'secondSubtitle', 'runs', 0, 'text').to_i
      @duration_text = response.dig('header', 'musicDetailHeaderRenderer', 'secondSubtitle', 'runs', 2, 'text')
      thumbnails = response.dig('header', 'musicDetailHeaderRenderer', 'thumbnail', 'croppedSquareThumbnailRenderer', 'thumbnail', 'thumbnails')
      @thumbnails = thumbnails.map { Thumbnail.new _1 }
      @playlist_url = response.dig('microformat', 'microformatDataRenderer', 'urlCanonical')
      track_contents = response.dig('contents', 'singleColumnBrowseResultsRenderer', 'tabs', 0, 'tabRenderer', 'content', 'sectionListRenderer', 'contents', 0, 'musicShelfRenderer', 'contents')
      @tracks = track_contents.map { Track.new _1 }
      @duration_seconds = @tracks.sum(&:duration_seconds)
      super()
    end
  end
end
