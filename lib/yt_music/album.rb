# frozen_string_literal: true

module YtMusic
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
      @year = extract_year_from_subtitle(subtitle)
      strapline_text_one = header.dig('straplineTextOne', 'runs')
      artist_contents = strapline_text_one&.filter { it['text'] != ' • ' }&.filter { it['text'] != '、' }
      return if artist_contents.blank?

      @artists = artist_contents.map { Artist.new it }

      @track_total_count = header.dig('secondSubtitle', 'runs', 0, 'text').to_i
      @duration_text = header.dig('secondSubtitle', 'runs', 2, 'text')
      thumbnails = header.dig('thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails')
      @thumbnails = thumbnails.map { Thumbnail.new it }
      @playlist_url = response.dig('microformat', 'microformatDataRenderer', 'urlCanonical')
      track_contents = response.dig('contents', 'twoColumnBrowseResultsRenderer', 'secondaryContents', 'sectionListRenderer', 'contents', 0, 'musicShelfRenderer', 'contents')
      @tracks = track_contents.map { Track.new it }
      @duration_seconds = @tracks.sum(&:duration_seconds)
      super()
    end

    private

    def extract_year_from_subtitle(subtitle)
      return nil unless subtitle

      last_element = subtitle.pop
      return nil unless last_element

      text = last_element['text']
      return nil unless text

      text.to_i.to_s
    end
  end
end
