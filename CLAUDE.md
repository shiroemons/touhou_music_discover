# CLAUDE.md

東方同人音楽を複数の配信サービス（Spotify / Apple Music / YouTube Music / LINE MUSIC）横断で管理する Rails アプリ。

## コマンド

- タスクは `Taskfile.yml` が正本で、`task <name>` で実行する（内部で `devbox run` を呼ぶ）。一覧は `task --list`
- `Makefile` は移行期間中の互換ラッパーなので、新しい手順や指示では使わない
- よく使うもの: `task up`（全サービス起動）/ `task health`（状態と URL の確認）/ `task test` / `task lint`
- rake タスクの直接実行は `devbox run -- bin/rails <task>`
- JS は yarn 1.22 を使う（bun は使わない）
- Rails のポートは 3000 が埋まっていると自動で切り替わる。URL は `task health` で確認する

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
- コミットは Conventional Commits の種別を英語で付け、説明は日本語で書く（例: `feat: ユーザー認証を追加`）
- PR のタイトルと説明は日本語で書く
- コミットや PR に `Generated with Claude Code` や `Co-Authored-By: Claude` を入れない
