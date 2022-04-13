# frozen_string_literal: true

module LineMusic
  class Artist < Base
    class << self
      def find(id)
        super(id, 'artist')
      end

      def albums(id, start: 1, display: 1000)
        path = "artist/#{id}/albums.v1?start=#{start}&display=#{display}"
        response = LineMusic.get path
        result = response.body['response']['result']['albums'].map { |a| Album.new a }
        insert_total(result, 'album', response.body)
        result
      end
    end

    attr_reader :artist_id, :artist_name, :track_count, :album_count,
                :video_count, :image_url, :like_count

    def initialize(props = {})
      @artist_id = props['artistId']
      @artist_name = props['artistName']
      @track_count = props['trackCount']
      @album_count = props['albumCount']
      @video_count = props['videoCount']
      @image_url = props['imageUrl']
      @like_count = props['likeCount']

      super()
    end
  end
end
