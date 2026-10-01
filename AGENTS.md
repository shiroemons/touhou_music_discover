# AGENTS.md

## Command Execution
- このプロジェクトの開発・テスト・lint・セットアップ系コマンドは、原則として `devbox run` 経由で実行する。
- 例: `devbox run bin/rails test`
- 例: `devbox run bin/rails db:migrate`
- 例: `devbox run yarn build`
- タスク定義は `Taskfile.yml` を正本とし、`task <name>` で実行する（各タスクは内部で `devbox run` を呼ぶ）。`Makefile` は移行期間中の互換ラッパーなので、新しい手順では使わない。
- ローカルDB、Redis、Solid Queue workerなど devbox 管理のサービスが必要な場合は、`task up` でバックグラウンド起動する。
- テストは `task test`、lint は `task lint`、DBバックアップは `task db:backup` で実行する。開発DBにデータ変更を加える作業の前には `task db:backup` を取る。
- `Taskfile.yml` は process-compose 管理ポートとして `53177` を使う。手動で `devbox services` を使う場合も、`devbox services up --env DEVBOX_PC_PORT_NUM=53177 -b --pcport 53177` と `devbox services ls --env DEVBOX_PC_PORT_NUM=53177` を優先する。
- 非TTY環境では `devbox services up` を単独実行しない。TUI起動で失敗するため、必ず `-b` を付ける。
- Railsへのアクセスが遅い、管理画面アクションが進まない、または応答しない場合は、まず `task health` / `task status` で `rails` / `jobs` / `postgresql` / `redis` と `http://localhost:3000/up` を確認する。
- `rails` が `Terminating` / `Pending` のまま残った場合は、まず `task recover` で `devbox services stop` から `devbox services up -b` まで実行して復旧する。
- `devbox services ls` では未起動なのに `3000` / `5432` / `6379` が LISTEN している場合は、devbox管理外の孤児プロセスが残っている。`task recover-force` で孤児プロセスを停止してから `devbox services up -b` で復旧する。
- RailsアプリのURLは通常 `http://localhost:3000`（3000番が使用中なら空きポートに自動で切り替わるため、`task health` の `URL` 行で確認する）。`localhost:5000` は macOS の `ControlCenter` が使うことがあるため、Rails確認には使わない。

## Git運用
- Conventional Commits形式を使用する（`feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`）。
- コミットメッセージの説明部分は明確な日本語で記述する（種別プレフィックスは英語のまま使用する）。
