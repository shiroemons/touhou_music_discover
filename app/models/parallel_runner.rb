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
# 実行モードは :processes をデフォルトのままにしている。理由は、対象の呼び出し箇所がいずれも
# 外部API (YtMusic / LineMusic / Spotify の HTTP 呼び出し) 待ちであり、YtMusic::Client や
# LineMusic::Client のシングルトンが保持するメモ化済み Faraday コネクションが、
# fork によってプロセスごとに分離されることで結果的にスレッドセーフに保たれているため。
# :threads に切り替えるとこれらの Faraday コネクションが本当に共有され、安全ではなくなる。
#
# ただし残存リスクもある: これらの処理は Solid Queue のワーカースレッドから呼ばれるため、
# マルチスレッドプロセスからの fork となる。fork の瞬間に他スレッドが握っていたミューテックス
# (例: Ruby の Logger 内部ミューテックス) は子プロセス側でロックされたまま解放されない可能性があり、
# これは fork-from-multithreaded-process 一般の既知の危険性で、この設計でも解消しきれていない。
module ParallelRunner
  # ワーカー数の単一の情報源。以前は6箇所にハードコードされていた。
  WORKERS = { ytmusic: 7, line_music: 4, spotify: 3 }.freeze

  MODE_OPTION_KEYS = { processes: :in_processes, threads: :in_threads }.freeze

  class << self
    # テストからワーカー数を強制するための上書き値 (nil で未設定)
    attr_accessor :forced_workers

    def each(records, workers:, mode: :processes, finish: nil, &)
      items = records.to_a
      count = effective_workers(workers)

      return run_inline(items, finish, &) if count <= 1

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

    # fork 前に親プロセスのアイドルDBコネクションをプールへ返すための保険。
    # 子プロセス側は ActiveSupport::ForkTracker がコネクションプールを破棄してくれる
    # (ActiveRecord の pool_config.rb を参照) ため、これはあくまで親プロセス側の念のための処置。
    # 対象レコードを materialize した後・fork の直前という、このタイミングでのみ実行すること。
    # そうしないと処理途中のトランザクションを中断してしまう恐れがある。
    def prepare_for_fork
      ActiveRecord::Base.connection_handler.clear_all_connections!(:all)
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
