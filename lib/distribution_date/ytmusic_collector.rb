# frozen_string_literal: true

module DistributionDate
  # YouTube Music側の動画メタデータ(YtMusic::Video)を取得し、
  # ytmusic_albums.distribution_track_metadataへ保存したうえで
  # YtmusicAlbum#recalculate_distribution! で配信日を集計し直す。
  #
  # 対象動画は ytmusic_albums.payload['tracks'] の video_id を正として決定する
  # (ytmusic_tracksの行はアルバム取り込みより遅れて作られるため、行の有無に集計が
  # 左右されないようにするため)。payloadが縮退していてtracksが無い場合だけ、
  # 従来どおりytmusic_tracksの行にフォールバックする。
  # video_idが一致するYtmusicTrack行が存在すれば、そちらのカラムも従来どおり更新する。
  #
  # 「どのアルバムを対象にするか」と「アルバム内のどの動画を取り直すか」は直交する概念であり、
  # それぞれ独立したオプションで制御する:
  #   - all:          true なら全アルバムを対象にする。false（既定）なら配信日が未確定
  #                   (YtmusicAlbum#distribution_missing 相当) のアルバムのみを対象にする。
  #   - only_missing: true（既定）なら distribution_track_metadata にその video_id の
  #                   fetched_at が未記録の動画だけ取得する。false なら（動画メタデータの
  #                   再取得・再集計のため）全動画を再取得する。
  #
  # 実行は既定でdry-run。`apply: true` を指定したときだけ実際にAPIを呼びDBを更新する。
  class YtmusicCollector
    DEFAULT_MAX_ATTEMPTS = 3
    DEFAULT_BASE_INTERVAL = 1.0

    # 一度のAPPLYで ParallelRunner.each に渡すスライスサイズ。
    SLICE_SIZE = 1000

    # 対象抽出条件: YtmusicAlbum.distribution_missing スコープと同じSQL
    # (配信日が未確定、または前回の集計がfailedだった行)。
    DISTRIBUTION_MISSING_SQL = "distributed_on IS NULL OR distribution_source = 'failed'"

    # collect_album 1件の処理結果。動画メタデータを何件取得できたかも一緒に集計したいため、
    # シンボル単体ではなくstatus/fetched_countを持つStructにしている。
    CollectOutcome = Struct.new(:status, :fetched_count, keyword_init: true)

    # rubocop:disable Metrics/ParameterLists -- 呼び出し側（rakeタスク・テスト）が個別に指定できる必要がある設定値のため、
    # オプションハッシュへの集約はせずキーワード引数のまま公開する。
    def initialize(apply: false, limit: nil, all: false, only_missing: true, workers: :ytmusic,
                   max_attempts: DEFAULT_MAX_ATTEMPTS, base_interval: DEFAULT_BASE_INTERVAL, out: $stdout,
                   progress_callback: nil)
      @apply = apply
      @limit = limit
      @all = all
      @only_missing = only_missing
      @workers = workers
      @max_attempts = max_attempts
      @base_interval = base_interval
      @out = out
      @progress_callback = progress_callback
    end
    # rubocop:enable Metrics/ParameterLists

    def run
      ids = target_ids
      print_header(ids.size)

      return finish_dry_run(ids) unless apply?

      finish_apply(ids)
    end

    # 子プロセス（forkモード時）またはテスト時は逐次実行の中で呼ばれる。
    # 例外はここで必ず握って :error を返し、他レコードの処理を止めない。
    def collect_album(id)
      ytmusic_album = YtmusicAlbum.unscoped.find_by(id:)
      return CollectOutcome.new(status: :not_found, fetched_count: 0) if ytmusic_album.nil?

      fetched_count = collect_videos(ytmusic_album)
      ytmusic_album.recalculate_distribution!

      status = ytmusic_album.distribution_source == 'failed' ? :failed : :updated
      CollectOutcome.new(status:, fetched_count:)
    rescue StandardError => e
      Rails.logger.error "DistributionDate::YtmusicCollector: album_id=#{id} browse_id=#{ytmusic_album&.browse_id.inspect} #{e.class}: #{e.message}"
      CollectOutcome.new(status: :error, fetched_count: 0)
    end

    private

    attr_reader :limit, :workers, :max_attempts, :base_interval, :out, :progress_callback

    def apply? = @apply
    def all? = @all
    def only_missing? = @only_missing

    # ------------------------------------------------------------------
    # 対象抽出（読み取り専用）
    # ------------------------------------------------------------------

    def target_ids
      scope = YtmusicAlbum.unscoped.order(:id)
      scope = scope.where(DISTRIBUTION_MISSING_SQL) unless all?
      scope = scope.limit(limit) if limit
      scope.pluck(:id)
    end

    # 対象アルバムに紐づく動画のうち、実際に取得しに行く件数を1本のsumで集計する。
    # payloadのvideo_idを正とし、payloadが縮退している（tracksが無い）アルバムだけ
    # ytmusic_tracksの行にフォールバックする（collect_videosの対象抽出と同じ考え方）。
    def pending_video_count(ids)
      rows = YtmusicAlbum.unscoped.where(id: ids).pluck(:id, :payload, :distribution_track_metadata)
      video_ids_by_album = {}
      fallback_album_ids = []

      rows.each do |album_id, payload, _track_metadata|
        video_ids = payload_video_ids(payload)
        if video_ids.empty?
          fallback_album_ids << album_id
        else
          video_ids_by_album[album_id] = video_ids
        end
      end
      merge_track_row_fallback!(video_ids_by_album, fallback_album_ids)

      return video_ids_by_album.values.sum(&:size) unless only_missing?

      fetched_video_ids_by_album = rows.to_h { |album_id, _payload, track_metadata| [album_id, fetched_video_ids(track_metadata)] }
      video_ids_by_album.sum do |album_id, video_ids|
        fetched = fetched_video_ids_by_album[album_id]
        video_ids.count { |video_id| fetched.exclude?(video_id) }
      end
    end

    # payloadが縮退していて対象動画が1件も取れなかったアルバムだけ、ytmusic_tracksの行から
    # video_idを補う（video_ids_by_albumを直接書き換える）。
    def merge_track_row_fallback!(video_ids_by_album, fallback_album_ids)
      return if fallback_album_ids.empty?

      YtmusicTrack.unscoped.where(ytmusic_album_id: fallback_album_ids).where.not(video_id: [nil, ''])
                  .pluck(:ytmusic_album_id, :video_id).each do |album_id, video_id|
        (video_ids_by_album[album_id] ||= []) << video_id
      end
    end

    # ------------------------------------------------------------------
    # dry-run
    # ------------------------------------------------------------------

    def finish_dry_run(ids)
      out.puts "取得予定トラック数: #{pending_video_count(ids)} 件" if ids.any?
      out.puts 'dry-run のため取得していません。実行するには APPLY=1 を付けて再実行してください。'
      build_result(target_count: ids.size, applied: false)
    end

    # ------------------------------------------------------------------
    # apply（1スライスごとに ParallelRunner.each で並列処理）
    # ------------------------------------------------------------------

    def finish_apply(ids)
      counters = Hash.new(0)
      fetched_videos = 0
      failed_album_browse_ids = []
      browse_id_by_id = YtmusicAlbum.unscoped.where(id: ids).pluck(:id, :browse_id).to_h
      processed = 0
      started_at = monotonic_now

      progress_callback&.call(current: 0, total: ids.size, message: 'YouTube Music 配信日集計を開始しています', reset: true)

      ids.each_slice(SLICE_SIZE) do |slice|
        finish_callback = lambda do |id, _index, outcome|
          counters[outcome.status] += 1
          fetched_videos += outcome.fetched_count
          failed_album_browse_ids << browse_id_by_id[id] if outcome.status == :failed && failed_album_browse_ids.size < 10
          processed += 1
          print_progress(processed, ids.size, counters)
          progress_callback&.call(current: processed, total: ids.size, message: progress_message(processed, ids.size, counters))
        end

        ParallelRunner.each(slice, workers:, finish: finish_callback) { |id| collect_album(id) }
      end

      elapsed = monotonic_now - started_at
      print_summary(ids.size, counters, elapsed, fetched_videos, failed_album_browse_ids)

      build_result(
        target_count: ids.size, applied: true, counters:, elapsed:,
        fetched_videos:, failed_album_browse_ids:
      )
    end

    # アルバム1件分の動画メタデータを取得し、distribution_track_metadataへ保存する。
    # 取得結果は成功・失敗を問わず必ず保存する（失敗した動画も published_on 等を nil にした
    # 要素として記録し、fetched_at で「いつ何を試したか」を追えるようにする）。
    # video_idが一致するYtmusicTrack行が存在すれば、そちらのカラムも従来どおり更新する。
    # 1動画の取得失敗はここで握りつぶし、そのトラックだけスキップして残りの処理を継続する
    # (握りつぶさずcollect_albumまで例外を伝播させると、そのアルバムの残りトラックの取得機会を失う)。
    def collect_videos(ytmusic_album)
      targets = video_targets(ytmusic_album)
      return 0 if targets.empty?

      metadata_by_video_id = index_metadata_by_video_id(ytmusic_album.distribution_track_metadata)
      tracks_by_video_id = ytmusic_album.ytmusic_tracks.index_by(&:video_id)
      fetched_count = 0

      targets.each do |target|
        next if only_missing? && metadata_by_video_id[target[:video_id]]&.dig('fetched_at').present?

        video = fetch_video(target[:video_id])
        metadata_by_video_id[target[:video_id]] = build_metadata_entry(target, video)
        fetched_count += 1 if video

        track = tracks_by_video_id[target[:video_id]]
        track.update_video_metadata(video) if track && video
      rescue StandardError => e
        Rails.logger.error "DistributionDate::YtmusicCollector: album_id=#{ytmusic_album.id} video_id=#{target[:video_id]} #{e.class}: #{e.message}"
      end

      ytmusic_album.update!(distribution_track_metadata: metadata_by_video_id.values)
      fetched_count
    end

    # 対象動画一覧を { video_id:, track_number: } の配列で返す。
    # payloadのvideo_idを正とし、payloadが縮退している（tracksが無い/空）ときだけ
    # ytmusic_tracksの行にフォールバックする。
    def video_targets(ytmusic_album)
      entries = payload_track_entries(ytmusic_album.payload)
      return entries if entries.any?

      track_row_entries(ytmusic_album)
    end

    def payload_track_entries(payload)
      Array(payload&.dig('tracks')).filter_map do |track|
        video_id = track['video_id'].presence
        next if video_id.nil?

        { video_id:, track_number: track['track_number'] }
      end
    end

    def payload_video_ids(payload)
      payload_track_entries(payload).map { |entry| entry[:video_id] }
    end

    def track_row_entries(ytmusic_album)
      ytmusic_album.ytmusic_tracks.filter_map do |track|
        next if track.video_id.blank?

        { video_id: track.video_id, track_number: track.track_number }
      end
    end

    def index_metadata_by_video_id(track_metadata)
      Array(track_metadata).index_by { |entry| entry['video_id'] }
    end

    # only_missingの差分抽出（dry-run側）で使う、取得済み（fetched_atが記録済み）のvideo_id一覧。
    def fetched_video_ids(track_metadata)
      Array(track_metadata).filter_map { |entry| entry['video_id'] if entry['fetched_at'].present? }
    end

    def build_metadata_entry(target, video)
      {
        'video_id' => target[:video_id],
        'track_number' => target[:track_number],
        'published_on' => video&.publish_date&.iso8601,
        'uploaded_on' => video&.upload_date&.iso8601,
        'original_released_on' => video&.release_date&.iso8601,
        'provided_by' => video&.provided_by,
        'art_track' => video ? video.art_track? : false,
        'fetched_at' => Time.current.iso8601
      }
    end

    # nilが返る間は指数バックオフ + ジッタを挟みながら max_attempts 回まで再取得する。
    # 最後まで取得できなければnilを返す（呼び出し元でそのトラックをスキップする）。
    def fetch_video(video_id)
      attempt = 1
      loop do
        video = YtMusic::Video.find(video_id)
        return video if video
        return nil if attempt >= max_attempts

        sleep(backoff_interval(attempt))
        attempt += 1
      end
    end

    def backoff_interval(attempt)
      RetryBackoff.interval(attempt, base_interval:)
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # rubocop:disable Metrics/ParameterLists -- dry-run/apply双方から呼ぶための共通の組み立て処理で、
    # 戻り値のキーがそのままこのメソッドの引数になっているため、ハッシュへの集約は可読性を下げる。
    def build_result(target_count:, applied:, counters: Hash.new(0), elapsed: 0.0, fetched_videos: 0,
                     failed_album_browse_ids: [])
      {
        target_count:, applied:, all: all?, only_missing: only_missing?, elapsed:,
        updated: counters[:updated], failed: counters[:failed],
        not_found: counters[:not_found], error: counters[:error],
        fetched_videos:, failed_album_browse_ids:
      }
    end
    # rubocop:enable Metrics/ParameterLists

    # ------------------------------------------------------------------
    # 出力
    # ------------------------------------------------------------------

    def print_header(target_count)
      out.puts '=' * 90
      out.puts "YouTube Music 配信日集計 (#{apply? ? 'APPLY: 実行します' : 'DRY-RUN: 実行しません'})"
      out.puts "対象モード: #{all? ? '全件' : '未取得のみ（distribution_missing）'}"
      out.puts "トラック取得モード: #{only_missing? ? '差分取得（distribution_track_metadataのfetched_atが未記録のみ）' : '全トラック再取得'}"
      out.puts "対象件数: #{target_count} 件"
      out.puts "ワーカー: #{workers.inspect}（ParallelRunner.effective_workers で解決。PARALLEL_WORKERSで上書き可）"
      out.puts "リトライ設定: max_attempts=#{max_attempts} / base_interval=#{base_interval}秒（指数バックオフ + ジッタ±30%）"
      out.puts '=' * 90
    end

    def print_progress(processed, total, counters)
      out.puts progress_message(processed, total, counters)
    end

    def progress_message(processed, total, counters)
      "処理中: #{processed}/#{total} " \
        "(更新:#{counters[:updated]} 配信日算出失敗:#{counters[:failed]} " \
        "未検出:#{counters[:not_found]} エラー:#{counters[:error]})"
    end

    def print_summary(total, counters, elapsed, fetched_videos, failed_album_browse_ids)
      out.puts '-' * 90
      out.puts "完了: 対象 #{total} 件 / 更新 #{counters[:updated]} 件 / " \
               "配信日算出失敗 #{counters[:failed]} 件 / " \
               "未検出 #{counters[:not_found]} 件 / エラー #{counters[:error]} 件"
      out.puts "取得した動画メタデータ数: #{fetched_videos} 件"
      out.puts format('経過時間: %<elapsed>.1f 秒', elapsed:)
      return if failed_album_browse_ids.blank?

      out.puts "配信日算出に失敗したbrowse_id (最大10件): #{failed_album_browse_ids.join(', ')}"
    end
  end
end
