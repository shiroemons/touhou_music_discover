# frozen_string_literal: true

module LineMusic
  class Album < Base
    class << self
      def find(id)
        super(id, 'album')
      end

      def tracks(id, start: 1, display: 1000)
        path = "album/#{id}/tracks.v1?start=#{start}&display=#{display}"
        response = LineMusic.get path
        result = response.body['response']['result']['tracks'].map { |t| Track.new t }
        insert_total(result, 'track', response.body)
        result
      end

      def search(query, start: 1, display: 100, sort: 'POPULAR')
        super(query, 'album', start:, display:, sort:)
      end
    end

    attr_reader :album_id, :album_title, :release_date, :image_url,
                :artist_total_count, :track_total_count, :is_adult,
                :is_streaming, :is_mobile_download, :is_download,
                :like_count, :user_action, :artists

    def initialize(props = {})
      @album_id = props['albumId']
      @album_title = props['albumTitle']
      @release_date = begin
        Date.parse(props['releaseDate']) if props['releaseDate']
      rescue ArgumentError
        Date.parse("#{props['releaseDate']}/01/01")
      end
      @image_url = props['imageUrl']
      @artist_total_count = props['artistTotalCount']
      @track_total_count = props['trackTotalCount']
      @is_adult = props['isAdult']
      @is_streaming = props['isStreaming']
      @is_mobile_download = props['isMobileDownload']
      @is_download = props['isDownload']
      @like_count = props['likeCount']
      @user_action = { is_purchased: props.dig('userAction', 'isPurchased') }
      @artists = (props['artists']&.map { |a| Artist.new a })

      super()
    end
  end
end
