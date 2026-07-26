# frozen_string_literal: true

module Dedupe
  # 配信プラットフォーム別テーブルに蓄積した重複行を安全に取り除く。
  #
  # 重複は `find_or_create_by!` に一意キー以外の属性まで渡していたことで発生している。
  # ここでは「同じ一意キーを持つ行」を1グループとして扱い、1行だけ残して他を削除する。
  #
  # 残す1行の基準:
  #   - 原則: created_at 昇順 → id 昇順で先頭（＝最古）を残す
  #   - 例外1: SpotifyTrackAudioFeature は created_at 降順 → id 昇順で先頭（＝最新）を残す。
  #     Spotifyの再解析によって tempo 等の値が更新されているため、新しい行のほうが正しい。
  #   - 例外2: LineMusicTrack も最新を残す。2022年に作成された行は ISRC が track_number に対して
  #     1つずれており、Spotify/Apple Music の (disc_number, track_number) → ISRC 対応と一致しない。
  #   - 例外3: YtmusicTrack は created_at では正しい行を選べない（同じ track_id に対して video_id が異なる）。
  #     親 ytmusic_albums.payload に載っている video_id を持つ行を優先し、一意に決まらない場合のみ最古に落とす。
  #
  # 子テーブルを持つ親（AppleMusicAlbum / YtmusicAlbum / SpotifyTrack）の loser を削除すると、
  # keeper へ付け替えられなかった子は `dependent: :destroy` で連鎖削除される。
  # この連鎖削除も「削除件数」として安全装置・サマリ・削除ログに算入する。
  #
  # 親テーブル（AppleMusicAlbum / YtmusicAlbum）は loser を削除する前に、グループ内で最も新しい行の
  # 属性を keeper へマージする。最古を残す方針のままでは、後から取得し直した正しい name / url /
  # release_date を捨ててしまうため。
  #
  # 実行は既定でdry-run。`apply: true` を指定したときだけ、安全装置を通過した場合に限り削除する。
  class PlatformRecords
    DEFAULT_MAX_DELETIONS = 1500
    DEFAULT_MAX_RATIO = 0.05

    # 一度のSQLで扱うキー・IDの最大数（WHERE句が肥大化しないように分割する）
    BATCH_SIZE = 200
    # dry-run時に表示する重複グループのサンプル件数
    SAMPLE_SIZE = 5

    # 重複親の削除に巻き込まれる子テーブルの定義。
    # unique_keys は「FK を除いた」子自身の一意キー。
    # 空配列の場合は「keeper 側に子が1件でもあれば付け替えない」という意味になる
    # （SpotifyTrackAudioFeature のように spotify_track_id 自体が一意キーであるケース）。
    Child = Struct.new(:model_name, :foreign_key, :unique_keys, keyword_init: true) do
      def model
        model_name.constantize
      end
    end

    # 重複除去の対象テーブル定義。
    #   keep                    : 残す1行の選び方（:oldest / :newest）
    #   keeper_selector         : created_at では決められないテーブル用。指定するとそのメソッドが keeper を選ぶ
    #   extra_columns           : keeper_selector が参照するために追加で取得する列
    #   merge_latest_attributes : loser 削除前にグループ内最新行の属性を keeper へマージするか
    Target = Struct.new(
      :model_name, :unique_keys, :keep, :child, :keeper_selector, :extra_columns, :merge_latest_attributes,
      keyword_init: true
    ) do
      def initialize(extra_columns: [], merge_latest_attributes: false, **rest)
        super
      end

      def model
        model_name.constantize
      end
    end

    # 処理順序は親テーブルが先。親を先に片付けることで、子テーブルの重複除去時には
    # 付け替え済みの状態を見られるようにする。
    TARGETS = [
      Target.new(
        model_name: 'AppleMusicAlbum',
        unique_keys: %i[apple_music_id],
        keep: :oldest,
        child: Child.new(model_name: 'AppleMusicTrack', foreign_key: :apple_music_album_id, unique_keys: %i[apple_music_id]),
        merge_latest_attributes: true
      ),
      Target.new(
        model_name: 'YtmusicAlbum',
        unique_keys: %i[album_id browse_id],
        keep: :oldest,
        child: Child.new(model_name: 'YtmusicTrack', foreign_key: :ytmusic_album_id, unique_keys: %i[track_id]),
        merge_latest_attributes: true
      ),
      Target.new(model_name: 'AppleMusicTrack', unique_keys: %i[apple_music_album_id apple_music_id], keep: :oldest),
      Target.new(
        model_name: 'SpotifyTrack',
        unique_keys: %i[spotify_album_id spotify_id],
        keep: :oldest,
        child: Child.new(model_name: 'SpotifyTrackAudioFeature', foreign_key: :spotify_track_id, unique_keys: [])
      ),
      # 2022年作成の行は ISRC が1つずれており、Spotify/Apple Music の (disc_number, track_number) → ISRC 対応と
      # 一致しない。実測では新しい行が 7/7 一致・古い行が 0/7 一致だったため最新を残す。
      Target.new(model_name: 'LineMusicTrack', unique_keys: %i[line_music_album_id line_music_id], keep: :newest),
      # 同じ track_id に対して video_id が異なる重複のため created_at では正しい行を選べない。
      # 親 ytmusic_albums.payload に載っている video_id を持つ行を優先する。
      Target.new(
        model_name: 'YtmusicTrack',
        unique_keys: %i[ytmusic_album_id track_id],
        keep: :oldest,
        keeper_selector: :select_ytmusic_track_keeper_first,
        extra_columns: %i[video_id]
      ),
      Target.new(model_name: 'SpotifyTrackAudioFeature', unique_keys: %i[spotify_track_id], keep: :newest)
    ].freeze

    # loser の destroy! に巻き込まれて消える子1行ぶんの記録。key は「列名 => 値」のハッシュ。
    CascadedChild = Struct.new(:id, :created_at, :key, keyword_init: true)

    # 削除対象1行ぶんの計画。
    # reassigned_child_ids は keeper へ付け替える子のid、cascaded_children は dependent: :destroy で道連れになる子。
    Loser = Struct.new(:id, :created_at, :reassigned_child_ids, :cascaded_children, keyword_init: true)

    # 同じ一意キーを持つ行の集まり。key は「列名 => 値」のハッシュ。
    #   keeper_reason   : keeper_selector で選んだ場合の選定理由（それ以外は nil）
    #   merge_source_id : 属性マージ元となるグループ内最新行のid（keeper自身が最新なら nil）
    #   attribute_merge : `{ source_id:, changes: { 列名 => { from:, to: } } }`。差分があるときだけ入る
    Group = Struct.new(:key, :keeper_id, :keeper_reason, :losers, :merge_source_id, :attribute_merge, keyword_init: true)

    # テーブル1つぶんの計画。child_total_count は子テーブルの総行数（子を持たないテーブルは nil）。
    Plan = Struct.new(:target, :total_count, :child_total_count, :groups, keyword_init: true) do
      def deletion_count
        groups.sum { |group| group.losers.size }
      end

      def reassignment_count
        groups.sum { |group| group.losers.sum { |loser| loser.reassigned_child_ids.size } }
      end

      # 実際に差分があり、keeper へ属性マージが起きるグループ数。
      def merge_count
        groups.count(&:attribute_merge)
      end

      # dependent: :destroy によって子テーブルから消える行数。
      def cascaded_count
        groups.sum { |group| group.losers.sum { |loser| loser.cascaded_children.size } }
      end

      def deletion_ratio
        return 0.0 if total_count.zero?

        deletion_count.to_f / total_count
      end

      # 子テーブル全体に対する連鎖削除の比率。自テーブルの削除比率とは独立に判定する。
      def cascaded_ratio
        return 0.0 if child_total_count.nil? || child_total_count.zero?

        cascaded_count.to_f / child_total_count
      end
    end

    SUMMARY_FORMAT = '%<model>-26s %<total>10s %<groups>12s %<deletions>10s %<cascaded>12s ' \
                     '%<reassignments>14s %<merges>12s %<keep>10s'

    # 属性マージのコピー対象から常に外す列。updated_at は update! が必ず現在時刻で上書きするため、
    # 差分として記録しても意味がない。
    NON_MERGEABLE_COLUMNS = %w[id created_at updated_at].freeze

    def initialize(apply: false, max_deletions: DEFAULT_MAX_DELETIONS, max_ratio: DEFAULT_MAX_RATIO, out: $stdout)
      @apply = apply
      @max_deletions = max_deletions
      @max_ratio = max_ratio
      @out = out
      @ytmusic_album_video_ids = {}
    end

    # プラン作成 → サマリ出力 → 安全装置チェック → (APPLY時のみ)実行 → ログ書き込み
    def run
      print_header
      plans = TARGETS.map { |target| build_plan(target) }
      print_summary(plans)
      print_samples(plans) unless apply?

      violations = safety_violations(plans)
      print_violations(violations)

      log_rows = []
      log_path = nil

      if violations.any?
        print_abort_notice
      elsif apply?
        log_rows = execute(plans)
        log_path = write_log(log_rows)
        print_deletion_counts(log_rows)
        out.puts "削除ログ: #{log_path}" if log_path
      else
        out.puts 'dry-run のため削除していません。実削除するには APPLY=1 を付けて再実行してください。'
      end

      build_result(plans:, violations:, log_rows:, log_path:)
    end

    private

    attr_reader :max_deletions, :max_ratio, :out

    def apply? = @apply

    # ------------------------------------------------------------------
    # プラン作成フェーズ（読み取り専用。DBは一切変更しない）
    # ------------------------------------------------------------------

    def build_plan(target)
      # default_scope の includes(:album).order(...) が集計・削除の邪魔になるため、常に unscoped を使う。
      total_count = target.model.unscoped.count
      child_total_count = target.child && target.child.model.unscoped.count

      groups = duplicate_records(target).group_by { |record| key_of(record, target.unique_keys) }
                                        .map { |key, records| build_group(key, records, target) }
      assign_child_plans(target, groups) if target.child
      assign_attribute_merges(target, groups) if target.merge_latest_attributes

      Plan.new(target:, total_count:, child_total_count:, groups:)
    end

    def build_group(key, records, target)
      ordered, reason = select_keeper(target, records)
      keeper, *losers = ordered

      Group.new(
        key:,
        keeper_id: keeper.id,
        keeper_reason: reason,
        losers: losers.map { |record| build_loser(record) },
        merge_source_id: merge_source_id_for(target, records, keeper.id)
      )
    end

    # keeper を先頭に並べた配列と、その選定理由（created_at 順に選んだ場合は nil）を返す。
    def select_keeper(target, records)
      return send(target.keeper_selector, records) if target.keeper_selector

      [sort_by_keep(records, target.keep), nil]
    end

    # 親アルバムの payload に載っている video_id を持つ行を優先する。
    # 一意に決まらない場合（0件 / 複数件）は created_at 最古へフォールバックする。
    def select_ytmusic_track_keeper_first(records)
      # ytmusic_album_id は一意キーの一部なので、グループ内の全行で同じ値になる。
      known_video_ids = ytmusic_album_video_ids(records.first[:ytmusic_album_id])
      matches = records.select { |record| known_video_ids.include?(record[:video_id]) }

      if matches.one?
        keeper = matches.first
        rest = records.reject { |record| record.id == keeper.id }
        return [[keeper, *sort_by_keep(rest, :oldest)], 'album.payloadのvideo_idと一致']
      end

      [sort_by_keep(records, :oldest), ytmusic_track_fallback_reason(matches)]
    end

    def ytmusic_track_fallback_reason(matches)
      return 'album.payloadに一致するvideo_idなし→created_at最古を採用' if matches.empty?

      'album.payloadに複数一致→created_at最古を採用'
    end

    def ytmusic_album_video_ids(album_id)
      @ytmusic_album_video_ids[album_id] ||= begin
        payload = YtmusicAlbum.unscoped.where(id: album_id).pick(:payload)
        (payload&.dig('tracks') || []).filter_map { |track| track['video_id'] }.to_set
      end
    end

    def build_loser(record)
      Loser.new(id: record.id, created_at: record.created_at, reassigned_child_ids: [], cascaded_children: [])
    end

    # keeper 自身がグループ内で最も新しい行なら、マージ元は不要なので nil を返す。
    def merge_source_id_for(target, records, keeper_id)
      return nil unless target.merge_latest_attributes

      newest = sort_by_keep(records, :newest).first
      newest.id == keeper_id ? nil : newest.id
    end

    # 削除前に keeper へコピーする属性差分を、グループ横断で1回のクエリにまとめて計算する。
    def assign_attribute_merges(target, groups)
      pairs = groups.filter_map { |group| group.merge_source_id && [group.keeper_id, group.merge_source_id] }
      return if pairs.empty?

      records_by_id = target.model.unscoped.where(id: pairs.flatten.uniq).index_by(&:id)
      mergeable_columns = target.model.column_names - NON_MERGEABLE_COLUMNS - target.unique_keys.map(&:to_s)

      groups.each do |group|
        next if group.merge_source_id.nil?

        changes = attribute_changes(
          keeper: records_by_id.fetch(group.keeper_id),
          source: records_by_id.fetch(group.merge_source_id),
          columns: mergeable_columns
        )
        group.attribute_merge = { source_id: group.merge_source_id, changes: } if changes.any?
      end
    end

    def attribute_changes(keeper:, source:, columns:)
      columns.each_with_object({}) do |column, changes|
        new_value = source[column]
        # コピー元が未設定の列は「情報がない」だけなので keeper の値を残す。
        next if new_value.nil? || new_value == keeper[column]

        changes[column] = { from: keeper[column], to: new_value }
      end
    end

    # 重複グループに属する行だけを取得する（id / created_at / 一意キー＋keeper選定に必要な列）。
    def duplicate_records(target)
      model = target.model
      unique_keys = target.unique_keys
      key_tuples = model.unscoped.group(unique_keys).having(Arel.sql('COUNT(*) > 1')).pluck(*unique_keys)
      # 一意キーが1列のときの pluck はスカラーを返すため、常にタプル（配列）に揃える。
      # 例: ['a', 'b'] -> [['a'], ['b']]
      key_tuples = key_tuples.zip if unique_keys.size == 1

      key_tuples.each_slice(BATCH_SIZE).flat_map do |tuples|
        model.unscoped.where(unique_keys => tuples).select(:id, :created_at, *unique_keys, *target.extra_columns).to_a
      end
    end

    # keep が :oldest なら created_at 昇順、:newest なら降順。同着のタイブレークは常に id 昇順。
    def sort_by_keep(records, keep)
      direction = keep == :newest ? -1 : 1

      records.sort do |a, b|
        created_at_order = (a.created_at <=> b.created_at) * direction
        created_at_order.zero? ? (a.id <=> b.id) : created_at_order
      end
    end

    # loser に紐づく子を「keeper へ付け替える分」と「連鎖削除される分」に振り分ける。
    # keeper が「既に持っている」一意キーの集合は、DBの実状態＋この実行中に付け替えを決めた分の両方で管理し、
    # 複数の loser が同じ一意キーの子を持つ場合は最初の1件だけを付け替える。
    def assign_child_plans(target, groups)
      child = target.child
      owner_ids = groups.flat_map { |group| [group.keeper_id, *group.losers.map(&:id)] }
      rows_by_owner = child_rows_by_owner(child, owner_ids)

      groups.each do |group|
        taken_keys = rows_by_owner.fetch(group.keeper_id, []).to_set { |row| row[:key] }

        group.losers.each do |loser|
          rows_by_owner.fetch(loser.id, []).each do |row|
            # keeper 側に同じ一意キーの子が既にある場合は付け替えず、
            # loser の destroy! 時に dependent: :destroy で一緒に消えるに任せる。
            if taken_keys.include?(row[:key])
              loser.cascaded_children << CascadedChild.new(**row)
            else
              taken_keys << row[:key]
              loser.reassigned_child_ids << row[:id]
            end
          end
        end
      end
    end

    def child_rows_by_owner(child, owner_ids)
      return {} if owner_ids.empty?

      columns = [:id, child.foreign_key, :created_at, *child.unique_keys]
      rows = owner_ids.each_slice(BATCH_SIZE).flat_map do |ids|
        child.model.unscoped.where(child.foreign_key => ids).order(:id).pluck(*columns)
      end

      rows.group_by { |row| row[1] }
          .transform_values do |owned|
            owned.map { |row| { id: row[0], created_at: row[2], key: child.unique_keys.zip(row[3..]).to_h } }
          end
    end

    def key_of(record, unique_keys)
      unique_keys.index_with { |column| record[column] }
    end

    # ------------------------------------------------------------------
    # 安全装置
    # ------------------------------------------------------------------

    # 直接削除（loser自身）と連鎖削除（dependent: :destroy で消える子）の両方を安全装置に算入する。
    def safety_violations(plans)
      violations = total_deletion_violations(plans)

      plans.each do |plan|
        violations << deletion_ratio_violation(plan) if plan.deletion_ratio > max_ratio
        violations << cascaded_ratio_violation(plan) if plan.target.child && plan.cascaded_ratio > max_ratio
      end

      violations
    end

    def total_deletion_violations(plans)
      direct = plans.sum(&:deletion_count)
      cascaded = plans.sum(&:cascaded_count)
      total = direct + cascaded
      return [] if total <= max_deletions

      ["合計削除予定件数 直接 #{direct} 件 + 連鎖 #{cascaded} 件 = 合計 #{total} 件 が上限 #{max_deletions} 件を超えています"]
    end

    def deletion_ratio_violation(plan)
      format(
        '%<model>s の削除予定比率 %<ratio>.4f (%<deletions>d/%<total>d) が上限 %<max_ratio>.4f を超えています',
        model: plan.target.model_name, ratio: plan.deletion_ratio,
        deletions: plan.deletion_count, total: plan.total_count, max_ratio:
      )
    end

    def cascaded_ratio_violation(plan)
      format(
        '%<child>s への連鎖削除予定比率 %<ratio>.4f (%<cascaded>d/%<total>d) が上限 %<max_ratio>.4f を超えています（親: %<parent>s）',
        child: plan.target.child.model_name, ratio: plan.cascaded_ratio,
        cascaded: plan.cascaded_count, total: plan.child_total_count,
        max_ratio:, parent: plan.target.model_name
      )
    end

    # ------------------------------------------------------------------
    # 実行フェーズ（APPLY=1 かつ安全装置を通過したときのみ）
    # ------------------------------------------------------------------

    # 全テーブルを1トランザクションで処理する。途中で例外が出れば全体がロールバックされる。
    # 戻り値は削除・マージの記録（削除ログにそのまま書き出す）。
    def execute(plans)
      log_rows = []

      ActiveRecord::Base.transaction do
        plans.each do |plan|
          model = plan.target.model
          child = plan.target.child

          plan.groups.each do |group|
            # loser を消す前に、最新行の属性を keeper へ取り込む。
            apply_attribute_merge(model, group, log_rows) if group.attribute_merge

            group.losers.each do |loser|
              # 先に処理した親テーブルの dependent: :destroy で既に消えている場合がある。
              # プランは実行前に一括作成しているため、ここで存在を確認してから削除する。
              record = model.unscoped.find_by(id: loser.id)
              next if record.nil?

              reassign_children(child, loser.reassigned_child_ids, group.keeper_id) if child
              record.destroy!
              log_rows << direct_deletion_log_row(model, group, loser)
              log_rows.concat(cascaded_deletion_log_rows(model, child, loser))
            end
          end
        end
      end

      log_rows
    end

    def apply_attribute_merge(model, group, log_rows)
      keeper = model.unscoped.find_by(id: group.keeper_id)
      return if keeper.nil?

      changes = group.attribute_merge[:changes]
      keeper.update!(changes.transform_values { |change| change[:to] })
      log_rows << {
        type: 'merge',
        table: model.table_name,
        id: group.keeper_id,
        source_id: group.attribute_merge[:source_id],
        changes:
      }
    end

    def reassign_children(child, child_ids, keeper_id)
      return if child_ids.empty?

      child.model.unscoped.where(id: child_ids).find_each do |record|
        record.update!(child.foreign_key => keeper_id)
      end
    end

    def direct_deletion_log_row(model, group, loser)
      {
        type: 'direct',
        table: model.table_name,
        id: loser.id,
        key: group.key,
        created_at: loser.created_at.iso8601,
        kept_id: group.keeper_id
      }
    end

    # dependent: :destroy で消えたはずの子を再クエリで確認し、実際に消えた分だけをログに残す。
    def cascaded_deletion_log_rows(parent_model, child, loser)
      return [] if child.nil? || loser.cascaded_children.empty?

      surviving_ids = surviving_child_ids(child, loser.cascaded_children.map(&:id))

      loser.cascaded_children.reject { |cascaded| surviving_ids.include?(cascaded.id) }.map do |cascaded|
        {
          type: 'cascaded',
          table: child.model.table_name,
          id: cascaded.id,
          key: cascaded.key,
          created_at: cascaded.created_at.iso8601,
          cascaded_from: { table: parent_model.table_name, id: loser.id }
        }
      end
    end

    def surviving_child_ids(child, ids)
      ids.each_slice(BATCH_SIZE).flat_map { |slice| child.model.unscoped.where(id: slice).pluck(:id) }.to_set
    end

    # 削除が正常にコミットされた場合のみ、JSON Lines形式で削除ログを残す。
    def write_log(rows)
      return nil if rows.empty?

      path = Rails.root.join("log/dedupe_platform_records_#{Time.current.strftime('%Y%m%d%H%M%S')}.log")
      FileUtils.mkdir_p(path.dirname)
      File.open(path, 'a') do |file|
        rows.each { |row| file.puts(row.to_json) }
      end

      path
    end

    # ------------------------------------------------------------------
    # 出力
    # ------------------------------------------------------------------

    def print_header
      newest_models = TARGETS.select { |target| target.keep == :newest }.map(&:model_name)
      selector_models = TARGETS.select(&:keeper_selector).map(&:model_name)
      merge_models = TARGETS.select(&:merge_latest_attributes).map(&:model_name)

      out.puts '=' * 90
      out.puts "プラットフォーム別テーブルの重複行クリーンアップ (#{apply? ? 'APPLY: 実削除します' : 'DRY-RUN: 削除しません'})"
      out.puts '残す1行の基準: created_at 昇順 → id 昇順の先頭（最古）'
      out.puts "  ただし #{newest_models.join(', ')} は created_at 降順 → id 昇順の先頭（最新）を残す（古い行の値が誤っているため）"
      out.puts "  #{selector_models.join(', ')} は親アルバムの payload に載っている video_id を持つ行を優先する"
      out.puts "  #{merge_models.join(', ')} は削除前にグループ内最新行の属性を keeper へマージする"
      out.puts "安全装置: 合計削除上限 #{max_deletions} 件（直接削除＋連鎖削除の合計）"
      out.puts "          テーブルごとの削除比率上限 #{max_ratio}（連鎖削除は子テーブル側の比率で別途判定）"
      out.puts '=' * 90
    end

    def print_summary(plans)
      out.puts format(SUMMARY_FORMAT, model: 'モデル', total: '総行数', groups: '重複グループ',
                                      deletions: '削除予定', cascaded: '連鎖削除予定',
                                      reassignments: '子付け替え予定', merges: '属性マージ予定', keep: '残す行')
      plans.each do |plan|
        out.puts format(
          SUMMARY_FORMAT,
          model: plan.target.model_name, total: plan.total_count, groups: plan.groups.size,
          deletions: plan.deletion_count, cascaded: plan.cascaded_count,
          reassignments: plan.reassignment_count, merges: plan.merge_count,
          keep: keep_label(plan.target)
        )
      end

      direct = plans.sum(&:deletion_count)
      cascaded = plans.sum(&:cascaded_count)
      out.puts format(
        SUMMARY_FORMAT,
        model: '合計', total: plans.sum(&:total_count), groups: plans.sum { |plan| plan.groups.size },
        deletions: direct, cascaded:, reassignments: plans.sum(&:reassignment_count),
        merges: plans.sum(&:merge_count), keep: '-'
      )
      out.puts "内訳: 直接削除 #{direct} 件 / 連鎖削除 #{cascaded} 件 / 合計 #{direct + cascaded} 件"
    end

    def keep_label(target)
      return 'payload優先' if target.keeper_selector

      target.keep == :newest ? '最新' : '最古'
    end

    def print_samples(plans)
      out.puts ''
      out.puts "重複グループのサンプル（各テーブル先頭 #{SAMPLE_SIZE} グループ / keeper の選定に payload を参照するテーブルは全グループ）"

      plans.each do |plan|
        next if plan.groups.empty?

        out.puts "  #{plan.target.model_name}:"
        sample_groups(plan).each { |group| out.puts "    #{sample_line(group)}" }
      end
    end

    # keeper_selector を持つテーブルは「どの行を残すか」が created_at から読み取れないため、
    # 選定結果を検証できるようにグループ数を絞らず全件表示する（数十グループ程度で収まる）。
    def sample_groups(plan)
      return plan.groups if plan.target.keeper_selector

      plan.groups.first(SAMPLE_SIZE)
    end

    def sample_line(group)
      key = group.key.map { |column, value| "#{column}=#{value}" }.join(', ')
      keeper = "keeper=#{group.keeper_id}"
      keeper += " (#{group.keeper_reason})" if group.keeper_reason
      parts = [key, keeper, "losers=#{group.losers.map(&:id).join(', ')}"]
      parts << merge_note(group.attribute_merge) if group.attribute_merge

      parts.join(' / ')
    end

    def merge_note(attribute_merge)
      "merge元=#{attribute_merge[:source_id]}(変更列: #{attribute_merge[:changes].keys.join(', ')})"
    end

    def print_deletion_counts(log_rows)
      direct = log_rows.count { |row| row[:type] == 'direct' }
      cascaded = log_rows.count { |row| row[:type] == 'cascaded' }

      out.puts "削除完了: 直接削除 #{direct} 件 / 連鎖削除 #{cascaded} 件 / 合計 #{direct + cascaded} 件"
      out.puts "属性マージ完了: #{log_rows.count { |row| row[:type] == 'merge' }} 件"
    end

    def print_violations(violations)
      return if violations.empty?

      out.puts ''
      out.puts '安全装置に抵触しました:'
      violations.each { |violation| out.puts "  - #{violation}" }
    end

    def print_abort_notice
      if apply?
        out.puts '中断しました。1行も削除していません。閾値を見直すか、MAX_DELETIONS / MAX_RATIO を明示的に指定してください。'
      else
        out.puts '（dry-run）APPLY=1 で実行した場合は上記の理由で中断し、1行も削除しませんでした。'
      end
    end

    def build_result(plans:, violations:, log_rows:, log_path:)
      direct_deletions = plans.sum(&:deletion_count)
      cascaded_deletions = plans.sum(&:cascaded_count)

      {
        applied: apply? && violations.empty?,
        aborted: violations.any?,
        abort_reasons: violations,
        total_rows: plans.sum(&:total_count),
        total_direct_deletions: direct_deletions,
        total_cascaded_deletions: cascaded_deletions,
        total_deletions: direct_deletions + cascaded_deletions,
        total_reassignments: plans.sum(&:reassignment_count),
        deleted_count: log_rows.count { |row| row[:type] == 'direct' },
        cascaded_deleted_count: log_rows.count { |row| row[:type] == 'cascaded' },
        # 実行フェーズで実際にマージした件数。dry-run では常に0で、予定件数は tables[...][:merges] を見る。
        total_merges: log_rows.count { |row| row[:type] == 'merge' },
        log_path: log_path&.to_s,
        tables: plans.to_h { |plan| [plan.target.model_name, table_result(plan)] }
      }
    end

    def table_result(plan)
      {
        total_rows: plan.total_count,
        duplicate_groups: plan.groups.size,
        deletions: plan.deletion_count,
        cascaded: plan.cascaded_count,
        reassignments: plan.reassignment_count,
        merges: plan.merge_count
      }
    end
  end
end
