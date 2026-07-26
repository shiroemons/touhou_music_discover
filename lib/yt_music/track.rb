# frozen_string_literal: true

module YtMusic
  class Track < Base
    # YouTube側の概数表記（例: "1.2万"）を数値化する際の桁の乗数。
    VIEW_COUNT_UNIT_MULTIPLIERS = { '千' => 1_000, '万' => 10_000, '億' => 100_000_000 }.freeze

    attr_reader :title, :video_id, :playlist_id, :url, :track_number, :artists, :duration, :duration_seconds,
                :view_count_text, :view_count

    def initialize(content, album_artists: nil)
      item = content['musicResponsiveListItemRenderer']
      flex_column = item.dig('flexColumns', 0, 'musicResponsiveListItemFlexColumnRenderer', 'text', 'runs', 0)
      @title = flex_column['text']
      @video_id = extract_video_id(item, flex_column)
      @playlist_id = extract_playlist_id(item, flex_column)
      @url = "https://music.youtube.com/watch?v=#{@video_id}&list=#{@playlist_id}" if @video_id && @playlist_id
      @track_number = extract_track_number(item)
      @artists = extract_artists(item, album_artists)
      @duration = item.dig('fixedColumns', 0, 'musicResponsiveListItemFixedColumnRenderer', 'text', 'runs', 0, 'text')
      if @duration
        mapped_increments = [1, 60, 3600].zip(@duration.split(':').reverse)
        @duration_seconds = mapped_increments.sum { |multiplier, time| multiplier * time.to_i }
      end
      @view_count_text = extract_view_count_text(item)
      @view_count = extract_view_count(@view_count_text)
      super()
    end

    def complete?
      video_id.present? && playlist_id.present? && track_number.to_i.positive?
    end

    def playable?
      video_id.present? && track_number.to_i.positive?
    end

    private

    # トラック別のアーティスト列（flexColumns[1]）が無い/空の場合は、呼び出し元から渡された
    # アルバムのアーティストにフォールバックする（単一アーティストのアルバムでは列自体が無いことが多い）。
    def extract_artists(item, album_artists)
      artist_contents = item.dig('flexColumns', 1, 'musicResponsiveListItemFlexColumnRenderer', 'text', 'runs')&.filter { it['text'] != '、' }
      return artist_contents.map { Artist.new it } if artist_contents.present?

      album_artists
    end

    def extract_view_count_text(item)
      item.dig('flexColumns', 2, 'musicResponsiveListItemFlexColumnRenderer', 'text', 'runs', 0, 'text')
    end

    # flexColumns[2]は再生回数以外（アーティスト名等）のこともあるため、数字を含まない文字列は
    # nilとして扱う。概数表記（千/万/億）のため、ここで得られる数値は近似値であり厳密値ではない。
    def extract_view_count(text)
      return nil if text.blank?

      normalized = text.tr('０-９', '0-9').tr('．', '.').delete(',')
      match = normalized.match(/(\d+(?:\.\d+)?)(#{VIEW_COUNT_UNIT_MULTIPLIERS.keys.join('|')})?/)
      return nil unless match

      multiplier = VIEW_COUNT_UNIT_MULTIPLIERS.fetch(match[2], 1)
      (match[1].to_f * multiplier).round
    end

    # YouTube側がスロットリング時に navigationEndpoint を欠いた縮退レスポンスを返すことがあるため、
    # videoIdは複数箇所からフォールバックして取得する。
    def extract_video_id(item, flex_column)
      flex_column.dig('navigationEndpoint', 'watchEndpoint', 'videoId').presence ||
        item.dig('playlistItemData', 'videoId').presence ||
        item.dig('overlay', 'musicItemThumbnailOverlayRenderer', 'content', 'musicPlayButtonRenderer',
                 'playNavigationEndpoint', 'watchEndpoint', 'videoId').presence
    end

    def extract_playlist_id(item, flex_column)
      flex_column.dig('navigationEndpoint', 'watchEndpoint', 'playlistId').presence ||
        item.dig('overlay', 'musicItemThumbnailOverlayRenderer', 'content', 'musicPlayButtonRenderer',
                 'playNavigationEndpoint', 'watchEndpoint', 'playlistId').presence
    end

    # 番号を捏造しないため、取得できない場合はnilを返す（0や配列位置からの推測はしない）。
    def extract_track_number(item)
      item.dig('index', 'runs', 0, 'text').presence&.to_i
    end
  end
end
