# frozen_string_literal: true

module YtMusic
  class SimpleSong
    attr_reader :title, :video_id, :album_browse_id, :album_title, :artists

    def initialize(item)
      @title = item.dig('flexColumns', 0, 'musicResponsiveListItemFlexColumnRenderer', 'text', 'runs', 0, 'text')
      metadata_runs = item.dig(
        'flexColumns', 1, 'musicResponsiveListItemFlexColumnRenderer', 'text', 'runs'
      ) || []
      album_run = metadata_runs.find do |run|
        run.dig('navigationEndpoint', 'browseEndpoint', 'browseId').to_s.start_with?('MPREb_')
      end
      @album_browse_id = album_run&.dig('navigationEndpoint', 'browseEndpoint', 'browseId')
      @album_title = album_run&.fetch('text', nil)
      @artists = metadata_runs.filter_map do |run|
        browse_id = run.dig('navigationEndpoint', 'browseEndpoint', 'browseId')
        Artist.new(run) if browse_id.present? && browse_id != @album_browse_id
      end
      @video_id = item.dig('playlistItemData', 'videoId').presence ||
                  item.dig('overlay', 'musicItemThumbnailOverlayRenderer', 'content', 'musicPlayButtonRenderer',
                           'playNavigationEndpoint', 'watchEndpoint', 'videoId')
      super()
    end
  end
end
