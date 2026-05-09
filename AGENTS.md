# AGENTS.md

## Command Execution
- このプロジェクトの開発・テスト・lint・セットアップ系コマンドは、原則として `devbox run` 経由で実行する。
- 例: `devbox run bin/rails test`
- 例: `devbox run bin/rails db:migrate`
- 例: `devbox run yarn build`
- ローカルDBやRedisなど devbox 管理のサービスが必要な場合は、`make up` または `devbox services up -b` でバックグラウンド起動する。
- `Makefile` は process-compose 管理ポートとして `53177` を使う。手動で `devbox services` を使う場合も、`devbox services up --env DEVBOX_PC_PORT_NUM=53177 -b --pcport 53177` と `devbox services ls --env DEVBOX_PC_PORT_NUM=53177` を優先する。
- 非TTY環境では `devbox services up` を単独実行しない。TUI起動で失敗するため、必ず `-b` を付ける。
- Railsへのアクセスが遅い、または応答しない場合は、まず `make health` で `rails` / `postgresql` / `redis` と `http://localhost:3000/up` を確認する。
- `rails` が `Terminating` / `Pending` のまま残った場合は、まず `make recover` で `devbox services stop` から `devbox services up -b` まで実行して復旧する。
- `devbox services ls` では未起動なのに `3000` / `5432` / `6379` が LISTEN している場合は、devbox管理外の孤児プロセスが残っている。`make recover-force` で孤児プロセスを停止してから `devbox services up -b` で復旧する。
- RailsアプリのURLは `http://localhost:3000`。`localhost:5000` は macOS の `ControlCenter` が使うことがあるため、Rails確認には使わない。
