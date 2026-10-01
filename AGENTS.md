# AGENTS.md

東方同人音楽を複数の配信サービス（Spotify / Apple Music / YouTube Music / LINE MUSIC）横断で管理する Rails アプリ。

Claude Code と Codex の共通の指示はこのファイルに書く（Claude Code は `CLAUDE.md` がなければ `AGENTS.md` を読む）。

## コマンド

- タスクは `Taskfile.yml` が正本で、`task <name>` で実行する（内部で `devbox run` を呼ぶ）。一覧は `task --list`
- `Makefile` は移行期間中の互換ラッパーなので、新しい手順や指示では使わない
- よく使うもの: `task up`（全サービスをバックグラウンド起動）/ `task health`（状態と URL の確認）/ `task test` / `task lint`
- task にないコマンドも `devbox run` 経由で実行する。rake タスクは `devbox run -- bin/rails <task>`
- JS は yarn 1.22 を使う（bun は使わない）

## サービスの起動と復旧

- DB、Redis、Solid Queue worker など devbox 管理のサービスが必要なら `task up` で起動する
- 非 TTY 環境では `devbox services up` を単独実行しない。TUI 起動で失敗するため、`task up` を使うか `-b` を付ける
- Rails の URL は本体で通常 `http://127.0.0.1:3000`。3000 番が使用中なら空きポートに切り替わるので、`task health` の `URL` 行で確認する。`localhost:5000` は macOS の ControlCenter が使うことがあるため、Rails の確認には使わない
- process-compose の管理ポートは本体で 53177。`devbox services` を直接使う場合は `--env DEVBOX_PC_PORT_NUM=<ポート>` を付ける（ワークツリーでは `.worktree.env` の値）
- Rails へのアクセスが遅い、管理画面アクションが進まない、応答しない場合は、`task health` / `task status` で `rails` / `jobs` / `postgresql` / `redis` と `/up` を確認する
- `rails` が `Terminating` / `Pending` のまま残ったら `task recover` で復旧する
- `devbox services ls` では未起動なのに Rails / PostgreSQL / Redis のポートが LISTEN している場合は、devbox 管理外の孤児プロセスが残っている。`task recover-force` で停止してから復旧する

## ワークツリー

- 並行作業用のワークツリーは、本体で `git wt --nocd <branch>` を実行して作る
- ワークツリーの作成・作業・片付けの前に、`worktree` スキル（`.agents/skills/worktree/SKILL.md`）を読んでその手順に従う
- ワークツリーではポートと DB が本体と分かれている。ポート番号を直接書かず、`PORT` / `PGPORT` / `REDIS_PORT` / `DEVBOX_PC_PORT_NUM` を使う
- 作業が終わったら、ワークツリーで `task down` を実行し、本体で `git wt -d <branch>` を実行して片付ける

## データ保護

- 開発 DB に書き込む作業（マイグレーション、データ修復、rake タスクなど）の前に `task db:backup` を取る
- `task db:restore` は DB を丸ごと上書きするため、実行前にユーザーに確認する

## 設計上の規約

- コアは Album（JAN コード）と Track（ISRC コード）。プラットフォーム別モデルは必ずこれらに紐付ける
- 主キーは UUID
- `is_touhou` で東方関連かどうかを判定する
- データ取得・運用操作は `app/models/admin/actions.rb` に `Admin::Actions::BaseAction` を継承したクラスとして実装する
- 管理アクションは Solid Queue のジョブで動くため、確認時は `jobs` サービスも起動しておく
- 外部 API の機密情報は `.env.development.local` に置く

## Git

- コードを変更したら、ブランチ作成 → コミット → push → PR 作成まで行う
- main にいる場合は、変更前に英語名のブランチを作る（例: `feature/...`、`fix/...`）
- コミットは Conventional Commits の種別（`feat:` / `fix:` / `docs:` / `test:` / `refactor:` / `chore:`）を英語で付け、説明は日本語で書く（例: `feat: ユーザー認証を追加`）
- PR のタイトルと説明は日本語で書く
- コミットや PR に、AI ツールの生成署名（`Generated with Claude Code` や `Co-Authored-By: Claude` など）を入れない
