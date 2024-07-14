# frozen_string_literal: true

module YTMusic
  class Album < Base
    class << self
      def find(id)
        response = super(id, 'album')
        return nil if response['error'].present?

        Album.new response
      end

      def search(query)
        super(query, 'albums')
      end
    end

    attr_reader :title, :type, :year, :artists,
                :track_total_count, :duration_text, :thumbnails, :playlist_url,
                :tracks, :duration_seconds

    def initialize(response)
      header = response.dig('contents', 'twoColumnBrowseResultsRenderer', 'tabs', 0, 'tabRenderer', 'content', 'sectionListRenderer', 'contents', 0, 'musicResponsiveHeaderRenderer')
      @title = header.dig('title', 'runs', 0, 'text')
      subtitle = header.dig('subtitle', 'runs')
      @type = subtitle&.shift&.dig('text')
      @year = subtitle&.pop&.dig('text')
      strapline_text_one = header.dig('straplineTextOne', 'runs')
      artist_contents = strapline_text_one&.filter { _1['text'] != ' • ' }&.filter { _1['text'] != '、' }
      return if artist_contents.blank?

      @artists = artist_contents.map { Artist.new _1 }

      @track_total_count = header.dig('secondSubtitle', 'runs', 0, 'text').to_i
      @duration_text = header.dig('secondSubtitle', 'runs', 2, 'text')
      thumbnails = header.dig('straplineThumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails')
      thumbnails ||= header.dig('thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails')
      @thumbnails = thumbnails.map { Thumbnail.new _1 }
      @playlist_url = response.dig('microformat', 'microformatDataRenderer', 'urlCanonical')
      track_contents = response.dig('contents', 'twoColumnBrowseResultsRenderer', 'secondaryContents', 'sectionListRenderer', 'contents', 0, 'musicShelfRenderer', 'contents')
      @tracks = track_contents.map { Track.new _1 }
      @duration_seconds = @tracks.sum(&:duration_seconds)
      super()
    end
  end
end
