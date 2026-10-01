# タスク定義の正本。一覧は just --list --list-submodules で表示する。
# just はレシピ名に ":" を使えないため、db / worktree などの名前空間は just/ 配下のモジュールに分けている。

set lazy
set quiet
set shell := ["bash", "-eo", "pipefail", "-c"]
set script-interpreter := ["bash", "-eo", "pipefail"]

# pipefail 下で `devbox services ls | grep -q` とすると、grep が先に終了して devbox が SIGPIPE で失敗し、
# 起動中でも未起動と判定される。そのため grep は -q を使わず出力を /dev/null に捨てて全行を読ませる。

# ワークツリーでは .worktree.env（scripts/worktree_setup が生成）のポートを使う。
# 本体では環境変数、なければ既定値（3000 / 5432 / 6379 / 53177）を使う。
pc_port := `scripts/worktree_env DEVBOX_PC_PORT_NUM 53177`
rails_port := `scripts/worktree_env PORT 3000`
pg_port := `scripts/worktree_env PGPORT 5432`
redis_port := `scripts/worktree_env REDIS_PORT 6379`

just := quote(just_executable()) + " --justfile " + quote(justfile())

mod console 'just/console.just'
mod db 'just/db.just'
mod worktree 'just/worktree.just'
mod data 'just/data.just'
mod lint 'just/lint.just'
mod import 'just/import.just'
mod export 'just/export.just'
mod change 'just/change.just'
mod associate 'just/associate.just'

alias restart := recover
alias ps := status
alias doctor := health

# タスク一覧を表示
[default]
help:
    {{ just }} --list --list-submodules

# devbox環境を初期化（bundle + yarn）
setup:
    devbox run setup

# devboxシェルに入る
shell:
    devbox shell

# 開発ツールのバージョンを表示
[script]
versions:
    echo "=== 開発ツールのバージョン ==="
    devbox run -- sh -c 'ruby -v && psql --version && redis-server --version && node --version && yarn --version' 2>/dev/null \
      | grep -v "東方同人音楽流通" \
      | sed 's/^ruby \([^ ]*\).*/  Ruby:       \1/' \
      | sed 's/^psql (PostgreSQL) /  PostgreSQL: /' \
      | sed 's/^Redis server v=\([^ ]*\).*/  Redis:      \1/' \
      | sed 's/^v\([0-9]\)/  Node.js:    v\1/' \
      | sed '/^[0-9]/s/^/  Yarn:       /'

# bundle installを実行
bundle:
    devbox run bundle

# Railsサーバーを起動
server:
    devbox run server

# 全サービスをバックグラウンドで起動（起動済みの場合はステータスを表示）
up: _start-unless-running && _wait-for-rails versions status health

# 全サービスをTUIモードで起動
tui:
    PGPORT={{ pg_port }} scripts/with_source_db_lock start devbox services up --env DEVBOX_PC_PORT_NUM={{ pc_port }} --env PORT={{ rails_port }} --pcport {{ pc_port }}

# Railsサーバーのログを表示
logs:
    tail -f log/development.log

# devboxサービスを停止
[script]
down:
    if devbox services ls --env DEVBOX_PC_PORT_NUM={{ pc_port }} 2>&1 | grep "Services running in process-compose" >/dev/null; then
      scripts/with_source_db_lock run devbox services stop --env DEVBOX_PC_PORT_NUM={{ pc_port }} 2>/dev/null
      echo "サービスを停止しました"
    else
      echo "サービスは起動していません"
    fi

# devboxサービスの状態を表示
[script]
status:
    if devbox services ls --env DEVBOX_PC_PORT_NUM={{ pc_port }} 2>&1 | grep "Services running in process-compose" >/dev/null; then
      devbox services ls --env DEVBOX_PC_PORT_NUM={{ pc_port }}
    else
      echo "サービスは起動していません。just up で起動できます。"
    fi

# Rails/DB/Redisの起動状態とHTTP応答を確認
[script]
health:
    rails_port="$(PORT={{ rails_port }} scripts/current_rails_port)"
    echo "=== devbox services ==="
    devbox services ls --env DEVBOX_PC_PORT_NUM={{ pc_port }} || true
    echo ""
    echo "=== listening ports ==="
    lsof -iTCP -sTCP:LISTEN -P 2>/dev/null | grep -E ":(${rails_port}|{{ pg_port }}|{{ redis_port }})([[:space:]]|$)" || true
    if ! devbox services ls --env DEVBOX_PC_PORT_NUM={{ pc_port }} 2>&1 | grep "Services running in process-compose" >/dev/null; then
      if (lsof -tiTCP:"${rails_port}" -sTCP:LISTEN >/dev/null 2>&1 || lsof -tiTCP:{{ pg_port }} -sTCP:LISTEN >/dev/null 2>&1 || lsof -tiTCP:{{ redis_port }} -sTCP:LISTEN >/dev/null 2>&1) && ! PORT={{ rails_port }} scripts/rails_health >/dev/null 2>&1; then
        echo ""
        echo "WARNING: devbox管理外の孤児プロセスがポートを掴んでいる可能性があります。just recover-force で掃除できます。"
      fi
    fi
    echo ""
    echo "=== HTTP health ==="
    echo "  URL    http://127.0.0.1:${rails_port}"
    curl -s -o /dev/null -w '  /up    status=%{http_code} time=%{time_total}s\n' "http://127.0.0.1:${rails_port}/up" || true
    curl -s -o /dev/null -w '  /admin status=%{http_code} time=%{time_total}s\n' "http://127.0.0.1:${rails_port}/admin" || true

# Terminating/Pendingなどから復旧するため全サービスを停止してバックグラウンド起動
recover: _stop _ensure-ports-free _start && _wait-for-rails health

# devbox管理外に残ったRails/PostgreSQL/Redisの孤児プロセスも停止して復旧
recover-force: _stop kill-orphan-ports _start && _wait-for-rails health

# 当該プロジェクトの孤児だけを停止し、他プロジェクトのプロセスは識別情報を表示
kill-orphan-ports:
    DEVBOX_PC_PORT_NUM={{ pc_port }} PORT={{ rails_port }} PGPORT={{ pg_port }} REDIS_PORT={{ redis_port }} scripts/with_source_db_lock run scripts/kill_orphan_ports

# テストを実行
test:
    devbox run test

[private]
[script]
_start-unless-running:
    if devbox services ls --env DEVBOX_PC_PORT_NUM={{ pc_port }} 2>&1 | grep "Services running in process-compose" >/dev/null; then
      echo "サービスは既に起動しています"
    else
      PGPORT={{ pg_port }} scripts/with_source_db_lock start devbox services up --env DEVBOX_PC_PORT_NUM={{ pc_port }} --env PORT={{ rails_port }} -b --pcport {{ pc_port }}
    fi

[private]
_stop:
    echo "devboxサービスを停止します"
    scripts/with_source_db_lock run devbox services stop --env DEVBOX_PC_PORT_NUM={{ pc_port }} 2>/dev/null || true

[private]
_start:
    echo "devboxサービスをバックグラウンドで起動します"
    PGPORT={{ pg_port }} scripts/with_source_db_lock start devbox services up --env DEVBOX_PC_PORT_NUM={{ pc_port }} --env PORT={{ rails_port }} -b --pcport {{ pc_port }}

[private]
[script]
_ensure-ports-free:
    if lsof -tiTCP:{{ pg_port }} -sTCP:LISTEN >/dev/null 2>&1 || lsof -tiTCP:{{ redis_port }} -sTCP:LISTEN >/dev/null 2>&1; then
      echo "devbox停止後も {{ pg_port }}/{{ redis_port }} のいずれかが使用中です。"
      echo "孤児プロセスを停止するには just recover-force を実行してください。"
      {{ just }} health
      exit 1
    fi

[private]
[script]
_wait-for-rails:
    echo "Railsの /up を待機します"
    for i in $(seq 1 30); do
      if PORT={{ rails_port }} scripts/rails_health; then
        echo "Rails is ready"
        exit 0
      fi
      sleep 1
    done
    echo "Rails did not become ready within 30 seconds"
    {{ just }} health
    exit 1
