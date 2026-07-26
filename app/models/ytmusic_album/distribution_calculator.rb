# frozen_string_literal: true

class YtmusicAlbum
  # `YtmusicAlbum#recalculate_distribution!` から呼ばれる集計ロジック。
  # HTTPは一切行わず、渡されたトラック相当のオブジェクト（ytmusic_tracks行、または
  # DistributionTrackMetadataRecordが持つdistribution_track_metadata由来のレコード）だけで完結する。
  # 呼び出し元がどちらを渡したかは source_of_truth として distribution_stats に記録するだけで、
  # 集計ロジック自体は集計元の種類を意識しない。
  # 候補が1件も無いときは、縮退した動画（YouTube側のスロットリングでmicroformatを欠いた
  # レスポンス）の有無で 'failed'（本当に判定不能）と 'degraded'（スロットリングで未確定・
  # 再取得すれば直る可能性がある）を区別する。
  # 詳細な集計ルールは docs/superpowers/specs/2026-07-26-ytmusic-distribution-date-design.md の
  # 「集計ロジック」章を参照。
  class DistributionCalculator
    Result = Struct.new(
      :distributed_on, :youtube_published_on, :original_released_on,
      :distribution_source, :distribution_stats,
      keyword_init: true
    )

    # 除外トラックの一覧は監査目的なので、件数が多くても追い切れるよう上限を設ける。
    EXCLUDED_VIDEO_ID_SAMPLE_LIMIT = 10

    def initialize(tracks, source_of_truth:)
      @tracks = tracks
      @source_of_truth = source_of_truth
    end

    def call
      candidates, source = select_candidates
      source = 'single_track' if candidates.size == 1

      published_on, tie_break = mode_with_tie_break(candidates.map(&:published_on))
      original_released_on, = mode_with_tie_break(candidates.filter_map(&:original_released_on))

      Result.new(
        distributed_on: published_on&.next_day(1),
        youtube_published_on: published_on,
        original_released_on:,
        distribution_source: source,
        distribution_stats: build_stats(candidates:, tie_break:)
      )
    end

    private

    # 候補の決定順序:
    #   1. Art Track かつ published_on ありのトラックが1件以上あればそれを採用（art_track_mode）
    #   2. 無ければ published_on がある全トラックにフォールバック（all_track_mode）
    #   3. それも無ければ候補なし。縮退した動画（track.degraded）が1件以上あれば 'degraded'
    #      （スロットリングで未確定・再取得すれば直る可能性がある）、無ければ 'failed'
    #      （本当に判定不能）を記録する
    def select_candidates
      art_track_candidates = @tracks.select { |track| track.art_track && track.published_on.present? }
      return [art_track_candidates, 'art_track_mode'] if art_track_candidates.any?

      all_track_candidates = @tracks.select { |track| track.published_on.present? }
      return [all_track_candidates, 'all_track_mode'] if all_track_candidates.any?

      [[], @tracks.any?(&:degraded) ? 'degraded' : 'failed']
    end

    # 最頻値を求め、同数タイのときは古い方を採用する。
    # 初出（最初に配信された動画）を、後から追加された再アップロードや先行公開MVより信頼するため。
    def mode_with_tie_break(dates)
      return [nil, false] if dates.empty?

      counts = dates.tally
      max_count = counts.values.max
      most_frequent_dates = counts.select { |_date, count| count == max_count }.keys

      [most_frequent_dates.min, most_frequent_dates.size > 1]
    end

    def build_stats(candidates:, tie_break:)
      excluded_tracks = @tracks - candidates

      {
        'total_tracks' => @tracks.size,
        'art_tracks' => @tracks.count(&:art_track),
        'fetched_tracks' => @tracks.count { |track| track.video_fetched_at.present? },
        'degraded_videos' => @tracks.count(&:degraded),
        'published_on_counts' => date_counts(@tracks.map(&:published_on)),
        'art_track_published_on_counts' => date_counts(@tracks.select(&:art_track).map(&:published_on)),
        'original_released_on_counts' => date_counts(candidates.map(&:original_released_on)),
        'excluded_video_ids' => excluded_tracks.first(EXCLUDED_VIDEO_ID_SAMPLE_LIMIT).map(&:video_id),
        'tie_break' => tie_break,
        'source_of_truth' => @source_of_truth
      }
    end

    def date_counts(dates)
      dates.compact.tally.transform_keys(&:iso8601)
    end
  end
end
