---
description: devbox開発環境のルールとベストプラクティス
globs:
  - devbox.json
  - process-compose.yaml
  - Makefile
  - .envrc
---

# devbox開発環境ルール

## 基本原則

- このプロジェクトの主要開発環境はdevboxである
- 全てのツール（Ruby, Node.js, PostgreSQL, Redis等）はdevbox経由で実行すること
- Docker環境は従来互換として残しているが、日常開発ではdevboxを使用する

## コマンド実行パターン

- Taskコマンド: `task <name>` → devbox経由で実行される（定義は `Taskfile.yml`、一覧は `task --list`）
- `Makefile` は移行期間中の互換ラッパー（`make <target>` → `task <name>`）。新しい手順や指示では `task` を使う
- 直接実行: `devbox run <script>` でdevbox.jsonのscriptsを呼び出す
- devboxシェル内: `devbox shell` に入れば直接コマンド実行可能
- Docker環境: `Dockerfile` / `docker-compose.yml` は残っているが、Task/Make の入口はない

## サービス管理

- `task tui`: 全サービスをTUIモードで起動（PostgreSQL, Redis, Rails, jobs, JS, CSS）
- `task up`: バックグラウンドで起動（非TTY環境ではこちらを使う）
- `task down`: サービス停止
- `task status` / `task health`: サービス状態とHTTP応答の確認
- `task recover` / `task recover-force`: Terminating/Pending や孤児プロセスからの復旧
- PostgreSQLはdevboxプラグインが自動管理

## パッケージ追加

- 新しいシステム依存パッケージは `devbox.json` の `packages` に追加する
- `devbox search <package>` でパッケージ名とバージョンを検索

## Rubyバージョン更新時の注意

- devbox の Ruby をパッチ更新しても、`BUNDLE_PATH`（`.devbox/virtenv/bundle`）に残った**ネイティブ拡張は古い Ruby の dylib にリンクされたまま**で、`bundle install` だけでは再コンパイルされない（gem のバージョンが変わらないため）
- この状態で起動すると `rails` / `jobs` プロセスが `LoadError: linked to incompatible ... libruby-<旧version>.dylib` でクラッシュループする。Rails のロガー初期化より前に落ちるため `log/development.log` には何も残らず原因が分かりにくい
- 対処: 以下を実行してネイティブ拡張を強制的に再コンパイルする

```bash
rm -rf .devbox/virtenv/bundle/ruby/<abi>   # 例: 4.0.0
rm -rf .devbox/virtenv/bootsnap/bootsnap
devbox run -- bash -c "bundle install"
```

- `.ruby-version` / `devbox.json` の `ruby` / `Dockerfile` の `FROM ruby:` は3箇所セットで更新する

## 環境変数

- devbox.jsonの `env` セクションで基本的な環境変数を設定
- 機密情報（APIキー等）は `.env.development.local` で管理（gitignore対象）
- direnvにより、ディレクトリに入ると自動でdevbox環境がアクティベートされる

## ポート衝突に注意

- devbox環境とDocker環境を同時に起動しないこと（ポート3000, 5432, 6379が衝突する）
- ワークツリーでは `.worktree.env`（`scripts/worktree_setup` が生成）のポートを devbox の init_hook と Taskfile が読み込む。ポートを固定値で書かず、`PORT` / `PGPORT` / `REDIS_PORT` / `DEVBOX_PC_PORT_NUM` を参照すること
