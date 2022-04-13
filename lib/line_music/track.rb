# frozen_string_literal: true

module LineMusic
  class Track < Base
    class << self
      def find(id)
        super(id, 'tracks')
      end
    end

    attr_reader :track_id, :track_title, :disc_number, :track_number,
                :artist_total_count, :listened_count, :artists,
                :album, :has_lyric, :is_streaming, :is_download,
                :is_mobile_download, :is_top_popular, :user_action,
                :like_count, :is_karaoke_enabled

    def initialize(props = {})
      @track_id = props['trackId']
      @track_title = props['trackTitle']
      @disc_number = props['discNumber']
      @track_number = props['trackNumber']
      @artist_total_count = props['artistTotalCount']
      @listened_count = props['listenedCount']
      @artists = (props['artists']&.map { |a| Artist.new a })
      @album = (Album.new props['album'] if props['album'])
      @has_lyric = props['hasLyric']
      @is_streaming = props['isStreaming']
      @is_download = props['isDownload']
      @is_mobile_download = props['isMobileDownload']
      @is_top_popular = props['isTopPopular']
      @user_action = { is_purchased: props.dig('userAction', 'isPurchased') }
      @like_count = props['likeCount']
      @is_karaoke_enabled = props['isKaraokeEnabled']

      super()
    end
  end
end
