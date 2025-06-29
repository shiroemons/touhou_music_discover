# frozen_string_literal: true

module YtMusic
  class Track < Base
    attr_reader :title, :video_id, :playlist_id, :url, :track_number, :artists, :duration, :duration_seconds

    def initialize(content)
      item = content['musicResponsiveListItemRenderer']
      flex_columns = item.dig('flexColumns', 0, 'musicResponsiveListItemFlexColumnRenderer', 'text', 'runs', 0)
      @title = flex_columns['text']
      @video_id = flex_columns.dig('navigationEndpoint', 'watchEndpoint', 'videoId')
      @playlist_id = flex_columns.dig('navigationEndpoint', 'watchEndpoint', 'playlistId')
      @url = "https://music.youtube.com/watch?v=#{@video_id}&list=#{@playlist_id}" if @video_id && @playlist_id
      @track_number = item.dig('index', 'runs', 0, 'text').to_i
      artist_contents = item.dig('flexColumns', 1, 'musicResponsiveListItemFlexColumnRenderer', 'text', 'runs')&.filter { it['text'] != '、' }
      @artists = artist_contents.map { Artist.new it } if artist_contents.present?
      @duration = item.dig('fixedColumns', 0, 'musicResponsiveListItemFixedColumnRenderer', 'text', 'runs', 0, 'text')
      if @duration
        mapped_increments = [1, 60, 3600].zip(@duration.split(':').reverse)
        @duration_seconds = mapped_increments.sum { |multiplier, time| multiplier * time.to_i }
      end
      super()
    end
  end
end
