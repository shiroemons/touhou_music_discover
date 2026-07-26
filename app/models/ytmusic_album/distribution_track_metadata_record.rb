# frozen_string_literal: true

class YtmusicAlbum
  # `ytmusic_albums.distribution_track_metadata`（JSON。日付はISO8601文字列）を、
  # DistributionCalculatorが期待するインターフェース（art_track/published_on/original_released_on/
  # video_id/video_fetched_at）を持つオブジェクトへ変換する。
  # これにより DistributionCalculator は集計元が ytmusic_tracks 行か distribution_track_metadata かを
  # 意識せず同じ集計ロジックで扱える。
  class DistributionTrackMetadataRecord
    Record = Struct.new(
      :video_id, :track_number, :published_on, :original_released_on, :art_track, :video_fetched_at, :degraded,
      keyword_init: true
    )

    def self.from_metadata(entries)
      Array(entries).map { |entry| build(entry) }
    end

    def self.build(entry)
      Record.new(
        video_id: entry['video_id'],
        track_number: entry['track_number'],
        published_on: parse_date(entry['published_on']),
        original_released_on: parse_date(entry['original_released_on']),
        art_track: entry['art_track'] == true,
        # entry['fetched_at']は取得を試みた日時であり、成功/失敗を問わず記録される。
        # ytmusic_tracks側のvideo_fetched_at（成功時のみ設定）とは意味が異なるため、
        # distribution_statsのfetched_tracksを集計元間で厳密に比較しないこと。
        video_fetched_at: entry['fetched_at'],
        degraded: entry['degraded'] == true
      )
    end

    def self.parse_date(value)
      return nil if value.blank?

      Date.iso8601(value)
    end
    private_class_method :build, :parse_date
  end
end
