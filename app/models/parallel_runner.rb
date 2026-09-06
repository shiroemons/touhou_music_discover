# frozen_string_literal: true

# Parallel gem の呼び出しを一箇所に集約するラッパー。
#
# ワーカー数の決定順序 (優先度の高い順):
#   1. ParallelRunner.forced_workers  … テスト用のエスケープハッチ。test_helper.rb で 1 に固定し、
#      全テストを逐次実行・決定的にするために使う。
#   2. ENV['PARALLEL_WORKERS']        … 実行環境全体での上書き (.githooks/pre-push が 1 を指定)。
#   3. 呼び出し側の workers: 引数      … 通常はここで WORKERS のキーを指定する。
# 最終的に [決定値, Parallel.processor_count].min で頭打ちにする。
#
# 実行モードは :processes をデフォルトのままにしている。Rails runner やバッチ処理では、外部API
# 待ちの処理をプロセス分離できるためである。ただし、Solid Queue のようなマルチスレッドの
# ワーカーから fork すると、他スレッドが保持するロックやDB接続を子プロセスが引き継いでしまう。
# 管理アクションからは `with_forking_disabled` を使い、fork を発生させない。
module ParallelRunner
  # ワーカー数の単一の情報源。以前は6箇所にハードコードされていた。
  WORKERS = { ytmusic: 7, line_music: 4, spotify: 3 }.freeze

  MODE_OPTION_KEYS = { processes: :in_processes, threads: :in_threads }.freeze
  FORKING_DISABLED_KEY = :parallel_runner_forking_disabled

  class << self
    # テストからワーカー数を強制するための上書き値 (nil で未設定)
    attr_accessor :forced_workers

    # Solid Queue のマルチスレッドワーカーからの fork を禁止する。
    #
    # fork 元の別スレッドが保持するDB接続やロックは子プロセスに安全に引き継げない。
    # 管理アクションでは同じワーカー内で逐次実行することで、ワーカーのheartbeat停止と
    # 実行中ジョブの再投入を防ぐ。
    def with_forking_disabled
      previous = Thread.current[FORKING_DISABLED_KEY]
      Thread.current[FORKING_DISABLED_KEY] = true
      yield
    ensure
      Thread.current[FORKING_DISABLED_KEY] = previous
    end

    def each(records, workers:, mode: :processes, finish: nil, &)
      items = records.to_a
      count = effective_workers(workers)

      validate_mode!(mode)
      mode = :inline if forking_disabled?

      return run_inline(items, finish, &) if mode == :inline || count <= 1

      prepare_for_fork if mode == :processes
      Parallel.each(items, parallel_options(mode, count, finish), &)
    end

    def reset_forced_workers!
      self.forced_workers = nil
    end

    def effective_workers(workers)
      configured = forced_workers || env_workers || resolve_workers(workers)
      [configured.to_i, Parallel.processor_count].min
    end

    private

    def forking_disabled?
      Thread.current[FORKING_DISABLED_KEY] == true
    end

    def validate_mode!(mode)
      return if mode == :inline || MODE_OPTION_KEYS.key?(mode)

      raise ArgumentError, "unknown mode: #{mode.inspect}"
    end

    def resolve_workers(workers)
      case workers
      when Symbol then WORKERS.fetch(workers)
      when Integer then workers
      else raise ArgumentError, "workers must be a Symbol in WORKERS or an Integer, got #{workers.inspect}"
      end
    end

    def env_workers
      ENV['PARALLEL_WORKERS'].presence&.to_i
    end

    def parallel_options(mode, count, finish)
      option_key = MODE_OPTION_KEYS.fetch(mode) { raise ArgumentError, "unknown mode: #{mode.inspect}" }
      { option_key => count, finish: }.compact
    end

    # fork 前に現在のスレッドが保持するDBコネクションをプールへ返すための保険。
    # 他のスレッドの接続まで切断すると、Solid Queueのheartbeatや別ジョブの処理を中断する。
    # 子プロセス側のプールは ActiveSupport::ForkTracker が破棄するため、全接続の切断は不要。
    def prepare_for_fork
      ActiveRecord::Base.connection_handler.clear_active_connections!(:all)
    end

    # Parallel gem を経由せず逐次実行する。finish コールバックの引数は
    # Parallel が渡すもの (item, index, result) と完全に同一にすること。
    def run_inline(items, finish)
      items.each_with_index do |item, index|
        result = yield(item)
        finish&.call(item, index, result)
      end
    end
  end
end
