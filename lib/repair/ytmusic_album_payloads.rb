# frozen_string_literal: true

module Repair
  # YouTube Music側のレート制限等により保存されてしまった「縮退レスポンス」(tracksのvideo_idが
  # 欠落した不完全なデータ) の ytmusic_albums.payload を、同じ browse_id を再取得して修復する。
  #
  # 縮退の判定・保存スキップは既に YtMusic::Album#degraded? / YtmusicAlbum#update_album に
  # 実装済みのため、ここでは「対象の抽出」「リトライしての再取得」「進捗集計」だけを担当する。
  #
  # 実行は既定でdry-run。`apply: true` を指定したときだけ実際にAPIを呼び直しDBを更新する。
  # `all: true` を指定すると劣化の有無を問わず全アルバムを再取得対象にする（パーサ改修の恩恵を
  # 既存payloadへ反映させたいとき用。回帰ガードにより既存payloadが悪化することはない）。
  class YtmusicAlbumPayloads
    DEFAULT_MAX_ATTEMPTS = 3
    DEFAULT_BASE_INTERVAL = 1.0

    # 一度のAPPLYで ParallelRunner.each に渡すスライスサイズ。
    SLICE_SIZE = 1000

    # バックオフ間隔に掛けるジッタの振れ幅（±30%）。
    JITTER_RANGE = -30..30

    # trackのtrack_numberが「欠落 / 空文字 / 0 / 数値として解釈できない値」であるかどうかの判定式。
    # 数値形式(-?[0-9]+)であることを正規表現で確認してから::intへキャストすることで、
    # 想定外の文字列が入っていてもキャスト例外を起こさず「track_number欠落」として扱う。
    TRACK_NUMBER_MISSING_SQL = <<~SQL.squish
      CASE WHEN (tr->>'track_number') ~ '^-?[0-9]+$' THEN (tr->>'track_number')::int ELSE 0 END = 0
    SQL

    # 対象抽出条件: tracksが配列でない/空、またはいずれかのtrackのvideo_idがnull、
    # またはいずれかのtrackのtrack_numberが欠落/0（古い縮退保存の残骸でtrack_numberだけが
    # 0のまま残っているケースを拾うため）の行。
    DEGRADED_CONDITION_SQL = <<~SQL.squish
      jsonb_typeof(payload->'tracks') IS DISTINCT FROM 'array'
         OR jsonb_array_length(payload->'tracks') = 0
         OR EXISTS (
              SELECT 1 FROM jsonb_array_elements(payload->'tracks') tr
              WHERE tr->>'video_id' IS NULL
                 OR #{TRACK_NUMBER_MISSING_SQL}
            )
    SQL

    # dry-run時の内訳集計用。相互排他な5分類（合計は必ず対象件数と一致する）。
    # CASEの分岐順は上から順に「tracks欠損」→「全トラックnull」→「一部null」→
    # 「video_idは揃っているがtrack_number欠落」の優先度で判定し、どれにも当てはまらない行を
    # 'healthy' とする。劣化のみモードでは対象が必ず DEGRADED_CONDITION_SQL を満たすため
    # 'healthy' には決して分類されず、全件モードのときだけ健全な行がここに入る。
    BREAKDOWN_CASE_SQL = <<~SQL.squish
      CASE
        WHEN jsonb_typeof(payload->'tracks') IS DISTINCT FROM 'array' OR jsonb_array_length(payload->'tracks') = 0
          THEN 'missing_tracks'
        WHEN NOT EXISTS (
          SELECT 1 FROM jsonb_array_elements(payload->'tracks') tr WHERE tr->>'video_id' IS NOT NULL
        ) THEN 'all_null'
        WHEN EXISTS (
          SELECT 1 FROM jsonb_array_elements(payload->'tracks') tr WHERE tr->>'video_id' IS NULL
        ) THEN 'partial_null'
        WHEN EXISTS (
          SELECT 1 FROM jsonb_array_elements(payload->'tracks') tr WHERE #{TRACK_NUMBER_MISSING_SQL}
        ) THEN 'missing_track_number'
        ELSE 'healthy'
      END
    SQL

    BREAKDOWN_LABELS = {
      'all_null' => '全トラックnull',
      'partial_null' => '一部null',
      'missing_tracks' => 'tracks欠損',
      'missing_track_number' => 'track_number欠落',
      'healthy' => '劣化なし'
    }.freeze

    # rubocop:disable Metrics/ParameterLists -- 呼び出し側（rakeタスク・テスト）が個別に指定できる必要がある設定値のため、
    # オプションハッシュへの集約はせずキーワード引数のまま公開する。
    def initialize(apply: false, limit: nil, workers: :ytmusic, max_attempts: DEFAULT_MAX_ATTEMPTS,
                   base_interval: DEFAULT_BASE_INTERVAL, sync_tracks: false, all: false, out: $stdout)
      @apply = apply
      @limit = limit
      @workers = workers
      @max_attempts = max_attempts
      @base_interval = base_interval
      @sync_tracks = sync_tracks
      @all = all
      @out = out
    end
    # rubocop:enable Metrics/ParameterLists

    def run
      ids = target_ids
      print_header(ids.size)

      return finish_dry_run(ids) unless apply?

      finish_apply(ids)
    end

    private

    attr_reader :limit, :workers, :max_attempts, :base_interval, :out

    def apply? = @apply
    def sync_tracks? = @sync_tracks
    def all? = @all

    # ------------------------------------------------------------------
    # 対象抽出（読み取り専用）
    # ------------------------------------------------------------------

    def target_ids
      scope = YtmusicAlbum.unscoped.order(:id)
      scope = scope.where(DEGRADED_CONDITION_SQL) unless all?
      scope = scope.limit(limit) if limit
      scope.pluck(:id)
    end

    # 「全トラックnull / 一部null / tracks欠損 / track_number欠落」の内訳を
    # 1本のSQL(CASE + GROUP BY)で集計する。
    def breakdown(ids)
      YtmusicAlbum.unscoped.where(id: ids).group(Arel.sql(BREAKDOWN_CASE_SQL)).count
    end

    # ------------------------------------------------------------------
    # dry-run
    # ------------------------------------------------------------------

    def finish_dry_run(ids)
      print_breakdown(breakdown(ids)) if ids.any?
      out.puts 'dry-run のため修復していません。実行するには APPLY=1 を付けて再実行してください。'
      build_result(target_count: ids.size, applied: false)
    end

    # ------------------------------------------------------------------
    # apply（1スライスごとに ParallelRunner.each で並列処理）
    # ------------------------------------------------------------------

    def finish_apply(ids)
      counters = Hash.new(0)
      skipped_browse_ids = []
      browse_id_by_id = YtmusicAlbum.unscoped.where(id: ids).pluck(:id, :browse_id).to_h
      processed = 0
      started_at = monotonic_now

      ids.each_slice(SLICE_SIZE) do |slice|
        finish_callback = lambda do |id, _index, outcome|
          counters[outcome] += 1
          skipped_browse_ids << browse_id_by_id[id] if outcome == :still_degraded && skipped_browse_ids.size < 10
          processed += 1
          print_progress(processed, ids.size, counters)
        end

        ParallelRunner.each(slice, workers:, finish: finish_callback) { |id| repair_album(id) }
      end

      elapsed = monotonic_now - started_at
      print_summary(ids.size, counters, elapsed, skipped_browse_ids)

      build_result(target_count: ids.size, applied: true, counters:, elapsed:, skipped_browse_ids:)
    end

    # 子プロセス（forkモード時）またはテスト時は逐次実行の中で呼ばれる。
    # 例外はここで必ず握って :error を返し、他レコードの処理を止めない。
    def repair_album(id)
      ytmusic_album = YtmusicAlbum.unscoped.find_by(id:)
      return :not_found if ytmusic_album.nil?

      # YtMusic::Album.findは、レスポンスにerrorがある場合だけでなく、YouTube上でアルバムが
      # 削除/視聴不可になりcontentsが欠落している場合もnilを返す。いずれも再試行では回復しない。
      album = fetch_album(ytmusic_album.browse_id)
      return :not_found if album.nil?

      url = "https://music.youtube.com/browse/#{ytmusic_album.browse_id}"
      return :still_degraded unless ytmusic_album.update_album(album, url)

      sync_tracks(ytmusic_album) if sync_tracks?
      :repaired
    rescue StandardError => e
      Rails.logger.error "Repair::YtmusicAlbumPayloads: id=#{id} browse_id=#{ytmusic_album&.browse_id.inspect} #{e.class}: #{e.message}"
      :error
    end

    # 縮退している間は指数バックオフ + ジッタを挟みながら max_attempts 回まで再取得する。
    # 最後まで縮退していた場合は、そのdegradedなalbumをそのまま返す（呼び出し元でstill_degraded判定）。
    def fetch_album(browse_id)
      attempt = 1
      loop do
        album = YtMusic::Album.find(browse_id)
        return album if album.nil? || !album.degraded?
        return album if attempt >= max_attempts

        sleep(backoff_interval(attempt))
        attempt += 1
      end
    end

    def backoff_interval(attempt)
      base_interval * (2**(attempt - 1)) * jitter_factor
    end

    def jitter_factor
      1 + (rand(JITTER_RANGE) / 100.0)
    end

    # 修復済みのpayloadを元に、track_numberで突き合わせて YtmusicTrack も同期する。
    # album.as_json を呼び直さず、update_album が既に保存した payload をそのまま使う。
    def sync_tracks(ytmusic_album)
      tracks_by_number = payload_tracks_by_number(ytmusic_album.payload['tracks'])
      return if tracks_by_number.empty?

      YtmusicTrack.unscoped.where(ytmusic_album_id: ytmusic_album.id).find_each do |ytmusic_track|
        next if ytmusic_track.track_number.to_i.zero?

        payload_track = tracks_by_number[ytmusic_track.track_number]
        ytmusic_track.update_track(payload_track) if payload_track
      end
    end

    def payload_tracks_by_number(tracks)
      Array(tracks).each_with_object({}) do |track, index|
        track_number = track['track_number']
        next if track_number.to_i.zero?

        index[track_number] = track
      end
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def build_result(target_count:, applied:, counters: Hash.new(0), elapsed: 0.0, skipped_browse_ids: [])
      {
        target_count:, applied:, all: all?, elapsed:,
        repaired: counters[:repaired], still_degraded: counters[:still_degraded],
        not_found: counters[:not_found], error: counters[:error],
        skipped_browse_ids:
      }
    end

    # ------------------------------------------------------------------
    # 出力
    # ------------------------------------------------------------------

    def print_header(target_count)
      out.puts '=' * 90
      out.puts "YouTube Music アルバムpayloadの縮退修復 (#{apply? ? 'APPLY: 実行します' : 'DRY-RUN: 実行しません'})"
      out.puts "対象モード: #{all? ? '全件（劣化の有無を問わない）' : '劣化のみ'}"
      out.puts "対象件数: #{target_count} 件"
      out.puts "ワーカー: #{workers.inspect}（ParallelRunner.effective_workers で解決。PARALLEL_WORKERSで上書き可）"
      out.puts "リトライ設定: max_attempts=#{max_attempts} / base_interval=#{base_interval}秒（指数バックオフ + ジッタ±30%）"
      out.puts "sync_tracks: #{sync_tracks? ? '有効' : '無効'}"
      out.puts '=' * 90
    end

    def print_breakdown(counts)
      out.puts '内訳（相互排他な分類。合計は対象件数と一致します）:'
      BREAKDOWN_LABELS.each do |key, label|
        out.puts "  #{label}: #{counts.fetch(key, 0)} 件"
      end
    end

    def print_progress(processed, total, counters)
      out.puts "処理中: #{processed}/#{total} " \
               "(修復:#{counters[:repaired]} 縮退:#{counters[:still_degraded]} " \
               "未検出:#{counters[:not_found]} エラー:#{counters[:error]})"
    end

    def print_summary(total, counters, elapsed, skipped_browse_ids)
      out.puts '-' * 90
      out.puts "完了: 対象 #{total} 件 / 修復 #{counters[:repaired]} 件 / " \
               "縮退のままスキップ #{counters[:still_degraded]} 件 / " \
               "取得失敗(未検出) #{counters[:not_found]} 件 / エラー #{counters[:error]} 件"
      out.puts format('経過時間: %<elapsed>.1f 秒', elapsed:)
      out.puts "今回スキップしたbrowse_id (最大10件): #{skipped_browse_ids.join(', ')}" if skipped_browse_ids.present?
    end
  end
end
