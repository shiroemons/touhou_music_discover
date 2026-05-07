# frozen_string_literal: true

require 'date'

module YtMusic
  class Video < Base
    class << self
      def find(video_id)
        body = YtMusic.youtube_body(video_id:)
        response = YtMusic.send_youtube_request('player', body:)
        return nil if response.body['error'].present?

        new(response.body)
      end
    end

    attr_reader :video_id, :title, :channel_id, :channel_name, :view_count,
                :publish_date, :published_at, :upload_date, :uploaded_at,
                :release_date, :payload

    def initialize(response)
      @payload = response
      video_details = response['videoDetails']
      microformat = response.dig('microformat', 'playerMicroformatRenderer')

      @video_id = video_details&.dig('videoId') || microformat&.dig('externalVideoId')
      @title = video_details&.dig('title') || microformat&.dig('title', 'simpleText')
      @channel_id = video_details&.dig('channelId') || microformat&.dig('externalChannelId')
      @channel_name = video_details&.dig('author') || microformat&.dig('ownerChannelName')
      @view_count = (video_details&.dig('viewCount') || microformat&.dig('viewCount'))&.to_i
      @published_at = parse_time(microformat&.dig('publishDate'))
      @publish_date = @published_at&.to_date
      @uploaded_at = parse_time(microformat&.dig('uploadDate'))
      @upload_date = @uploaded_at&.to_date
      @release_date = extract_release_date(video_details&.dig('shortDescription') || microformat&.dig('description', 'simpleText'))
      super()
    end

    private

    def parse_time(value)
      return nil if value.blank?

      Time.zone.parse(value)
    end

    def extract_release_date(description)
      match = description&.match(/^Released on:\s*(\d{4}-\d{2}-\d{2})$/)
      return nil unless match

      Date.iso8601(match[1])
    end
  end
end
