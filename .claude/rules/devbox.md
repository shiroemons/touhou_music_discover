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

- Makefileコマンド: `make <command>` → devbox経由で実行される
- 直接実行: `devbox run <script>` でdevbox.jsonのscriptsを呼び出す
- devboxシェル内: `devbox shell` に入れば直接コマンド実行可能
- Docker環境: `make docker-<command>` で従来のDocker経由実行

## サービス管理

- `devbox services up` / `make tui`: 全サービスをTUIモードで起動（PostgreSQL, Redis, Rails, JS, CSS）
- `devbox services up -b` / `make up`: バックグラウンドで起動
- `devbox services stop` / `make down`: サービス停止
- PostgreSQLはdevboxプラグインが自動管理

## パッケージ追加

- 新しいシステム依存パッケージは `devbox.json` の `packages` に追加する
- `devbox search <package>` でパッケージ名とバージョンを検索

## 環境変数

- devbox.jsonの `env` セクションで基本的な環境変数を設定
- 機密情報（APIキー等）は `.env.development.local` で管理（gitignore対象）
- direnvにより、ディレクトリに入ると自動でdevbox環境がアクティベートされる

## ポート衝突に注意

- devbox環境とDocker環境を同時に起動しないこと（ポート3000, 5432, 6379が衝突する）
