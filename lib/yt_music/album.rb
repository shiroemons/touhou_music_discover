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
      # straplineTextOneが欠落した縮退レスポンスでも空配列を設定し、以降の項目を組み立てる
      # （縮退の検出はdegraded?に任せる）。
      @artists = artist_contents.present? ? artist_contents.map { Artist.new it } : []

      @track_total_count = header.dig('secondSubtitle', 'runs', 0, 'text').to_i
      @duration_text = header.dig('secondSubtitle', 'runs', 2, 'text')
      thumbnails = header.dig('thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails')
      @thumbnails = thumbnails.map { Thumbnail.new it }
      @playlist_url = response.dig('microformat', 'microformatDataRenderer', 'urlCanonical')
      track_contents = response.dig('contents', 'twoColumnBrowseResultsRenderer', 'secondaryContents', 'sectionListRenderer', 'contents', 0, 'musicShelfRenderer', 'contents')
      @tracks = track_contents.map { Track.new it, album_artists: @artists }
      @duration_seconds = @tracks.sum(&:duration_seconds)
      super()
    end

    # YouTube側の縮退レスポンス（全トラックのvideo_id/track_numberが欠落した完全な取得失敗）を検知する。
    # 一部のトラックだけplaylist_idが欠けている等、再生に支障のない部分的な欠落は縮退とみなさない
    # （回帰ガードはYtmusicAlbum#update_album側で別途行う）。
    def degraded?
      tracks.blank? || tracks.none?(&:playable?)
    end

    # 再生可能（video_idとtrack_numberが揃っている）なトラックの件数。
    def playable_track_count
      Array(tracks).count(&:playable?)
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
