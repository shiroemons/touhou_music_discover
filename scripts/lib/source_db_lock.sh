# shellcheck shell=sh
#
# 本体の開発DBを置く PostgreSQL の起動・停止を、本体のサービス操作とワークツリーのセットアップで
# 直列化するロック。ロックは git の共通ディレクトリに置くので、本体と全ワークツリーで共有される。
# 呼び出し側で set -eu を有効にし、source_db_lock_init <プロジェクトのパス> を呼んでから使う。

source_db_lock_timeout=600
source_db_lock_holding=false

source_db_lock_init() {
  source_db_lock_dir="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)/worktree-source-db.lock"
}

# ロックを取る。保持者として記録する PID を引数で渡せる（省略時は呼び出したシェル）。
source_db_lock_acquire() {
  source_db_lock_waited=0
  until mkdir "$source_db_lock_dir" 2>/dev/null; do
    source_db_lock_holder="$(cat "$source_db_lock_dir/pid" 2>/dev/null || true)"
    if [ -n "$source_db_lock_holder" ] && ! kill -0 "$source_db_lock_holder" 2>/dev/null; then
      echo "終了したプロセス（PID ${source_db_lock_holder}）が残したロックを解除します"
      rm -f "$source_db_lock_dir/pid"
      rmdir "$source_db_lock_dir" 2>/dev/null || true
      continue
    fi
    if [ "$source_db_lock_waited" -eq 0 ]; then
      echo "本体の PostgreSQL を別の処理（ワークツリーのセットアップか本体のサービス操作）が使っているため、終わるまで待ちます"
    fi
    source_db_lock_waited=$((source_db_lock_waited + 1))
    if [ "$source_db_lock_waited" -ge "$source_db_lock_timeout" ]; then
      echo "${source_db_lock_timeout} 秒待ってもロックを取得できません。他に実行中のものがなければ $source_db_lock_dir を削除してください。" >&2
      exit 1
    fi
    sleep 1
  done
  echo "${1:-$$}" > "$source_db_lock_dir/pid"
  source_db_lock_holding=true
}

# 保持者の PID を書き換える。ロックをバックグラウンドのプロセスに引き継ぐときに使う。
source_db_lock_handover() {
  echo "$1" > "$source_db_lock_dir/pid"
}

source_db_lock_release() {
  if [ "$source_db_lock_holding" = true ]; then
    rm -f "$source_db_lock_dir/pid"
    rmdir "$source_db_lock_dir" 2>/dev/null || true
    source_db_lock_holding=false
  fi
}
