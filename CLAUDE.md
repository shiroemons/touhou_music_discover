# CLAUDE.md

このファイルは、このリポジトリで作業する Claude Code（claude.ai/code）向けのガイドです。

## プロジェクト概要

touhou_music_discover（東方同人音楽流通）は、複数の配信プラットフォーム（Spotify、Apple Music、YouTube Music、LINE MUSIC）にある東方同人音楽を追跡・管理する Rails アプリケーション。アルバムとトラックを統合したデータベースに、プラットフォームごとのメタデータを紐付けて保持する。

## 主要なアーキテクチャ

### コアモデルと関連
- **Album**（JAN コード）→ 複数の **Track**（ISRC コード）を持つ
- プラットフォーム別モデル（SpotifyAlbum、AppleMusicAlbum など）は、コアの Album / Track に紐付く
- **Original** → **OriginalSong** → **TracksOriginalSong** → **Track**（東方の原作・原曲との対応）
- **Circle**（同人サークル）← **CirclesAlbum** → **Album**

### 管理画面
gem を使わない自作の管理画面で、`/admin` にマウントしている。コントローラは `app/controllers/admin/` 配下。データ取得や運用操作は、`app/models/admin/actions.rb` に `Admin::Actions::BaseAction` を継承したアクションクラスとして定義する。用途は次のとおり。
- 配信プラットフォームからのデータ取得
- 一括操作
- データのエクスポート / インポート

管理アクションは Solid Queue のジョブとして非同期に実行されるため、Rails と一緒に `jobs` サービスも起動しておく必要がある（`task up` / `task tui` なら両方起動する）。

## よく使う開発コマンド

タスクは `Taskfile.yml` に定義し、[Task](https://taskfile.dev/)（`task` コマンド。`mise install` で導入）で実行する。各タスクは内部で `devbox run` を呼ぶ。全タスクは `task --list` で確認できる。

`Makefile` は `task` に転送するだけの、移行期間中の互換ラッパー（例: `make db-dump` → `task db:backup`）。新しい手順や指示では使わない。

### セットアップと開発（devbox）
```bash
task setup         # 依存パッケージのインストール（bundle + yarn）
task tui           # 全サービスをTUIモードで起動（PostgreSQL + Redis + Rails + jobs + JS/CSS）
task up            # 全サービスをバックグラウンドで起動
task down          # 全サービスを停止
task status        # サービスの状態を表示
task health        # Rails/DB/Redisの起動状態とHTTP応答を確認
task recover       # Terminating/Pendingなどから復旧
task server        # Railsサーバーのみ起動
task console       # Railsコンソール
task shell         # devboxシェルに入る
```

Rails は通常 http://127.0.0.1:3000 で起動するが、3000番ポートが使用中なら空きポートに自動で切り替わる。実際の URL は `task health` の `URL` 行で確認する。

JSのパッケージマネージャーはyarn 1.22を使用する（bunは使用しない）。

### データベース操作
```bash
task db:migrate    # マイグレーション実行
task db:rollback   # ロールバック
task db:seed       # マスターデータ投入（originals, circles, artists）
task db:backup     # データベースバックアップ（tmp/data/touhou_music_discover-<日時>.bak）
task db:restore    # 最新のバックアップからリストア（BACKUP_FILE=<path> で指定可）
```

開発 DB にデータ変更を加える作業（マイグレーション、データ修復、rake タスクなど）の前には `task db:backup` を取る。

### テストとコード品質
```bash
task test          # テスト実行
task lint          # Rubocop実行
task lint:fix      # Rubocop自動修正
```

### プラットフォームからのデータ収集
プラットフォームごとに、データ取得用の rake タスクがある。
- `spotify:fetch_touhou_albums` - 「東方同人音楽流通」レーベルのアルバムを取得
- `apple_music:fetch_artist_albums` - アーティスト ID からアルバムを取得
- `ytmusic:search_albums_and_save` - アルバムを検索して保存
- `line_music:search_albums_and_save` - アルバムを検索して保存

実行方法: `devbox run -- bin/rails [task_name]`

### データのエクスポート
エクスポート用の rake タスクは Task でラップしている（例: `task export:for-algolia`、`task export:to-random-touhou-music`、`task export:all`）。全一覧は `task --list` で確認する。

### Docker 環境（旧来）
`Dockerfile` / `docker-compose.yml` は互換のために残しているが、Task / Make からの入口はない。日常の開発は devbox で行い、Docker と devbox を同時に起動しない（ポート 3000 / 5432 / 6379 が衝突する）。

## 外部 API 連携

### Spotify
- `lib/spotify_api/` に 3 層構成の自作クライアントがある: 認証（Client Credentials のアプリトークンを扱う `Config`、Redis に保存したユーザートークンを自動更新する `UserSession`）→ HTTP（Faraday ベースの `Client`。ステータスコードをエラークラスに対応付ける）→ リソース（`Album` / `Track` / `Playlist` / `AudioFeatures`。JSON とページングは `Response` / `Page` でラップ）
- OAuth ログイン（ユーザーの Spotify アカウント連携）は `lib/omniauth/strategies/spotify.rb`（`OmniAuth::Strategies::OAuth2` のサブクラス）で処理する
- `app/models/spotify_client/`（Album / Track / AudioFeatures と、それぞれの `native_backend.rb`）は、`SpotifyApi` を呼んで一括取得・保存するアプリ層で、`Admin::Actions::*` から使う
- オーディオ特徴量（tempo、energy など）も取得する
- 主な取得元は「東方同人音楽流通」レーベル

### Apple Music
- API クライアントは `lib/apple_music/`、アプリ層は `app/models/apple_music_client/`
- 必要な環境変数: `APPLE_MUSIC_SECRET_KEY`（または `APPLE_MUSIC_SECRET_KEY_PATH`）、`APPLE_MUSIC_TEAM_ID`、`APPLE_MUSIC_MUSIC_ID`（`APPLE_MUSIC_STOREFRONT` は既定値 `jp`）。機密情報は `.env.development.local` に置く

### YouTube Music と LINE MUSIC
- 公式 gem を使わない自作実装
- `lib/yt_music/` と `lib/line_music/` にある

## Lint
- Ruby のコードスタイルは Rubocop で確認する
- 設定は標準的な Rails の慣習に従う
- 確認は `task lint`
- 自動修正は `task lint:fix`

## 主なワークフロー

1. **新しいアルバムの追加**: 管理アクション（`Admin::Actions::*`）でプラットフォームから取得し、サークルや原曲と紐付ける
2. **データのエクスポート**: Algolia 検索用やランダム選曲アプリ用の出力には `task export:*` を使う
3. **プラットフォーム情報の更新**: プラットフォームごとに更新用の管理アクションがあり、メタデータを最新化する

## 重要な規約

- プラットフォーム別モデルは、必ずコアの Album / Track に紐付ける
- 主キーには UUID を使う
- アルバムは JAN コード、トラックは ISRC コードで識別する
- 東方フラグ（`is_touhou`）で、実際に東方関連のコンテンツかどうかを判定する
- データ取得処理は一貫性を保つため、`app/models/admin/actions.rb` に `Admin::Actions::BaseAction` を継承したアクションクラスとして実装する

## 開発の流れ
コードを変更するときは次の手順で進める。
1. main ブランチにいる場合は、変更前に新しいブランチを作る
2. 変更を加える
3. 日本語のわかりやすいメッセージでコミットする
4. リモートリポジトリに push する
5. レビュー用の Pull Request を日本語で作成する

これにより、コードの変更が適切にレビューされ、バージョン管理で追跡できる。

### コミットと Pull Request のガイドライン
- **コミットメッセージ**: Conventional Commits の種別プレフィックスを英語で付け（`feat:`、`fix:`、`docs:`、`test:`、`refactor:`、`chore:`）、説明は日本語で書く
- **Pull Request のタイトルと説明**: 日本語で書く
- **ブランチ名**: 内容がわかる英語の名前にする（例: `feature/add-feature-name`、`fix/bug-description`）
- **含めないもの**: コミットメッセージに `🤖 Generated with [Claude Code]` や `Co-Authored-By: Claude` を入れない

コミットメッセージの例:
```
feat: ユーザー認証システムを追加

- JWTトークンによる認証を実装
- ログイン/ログアウトAPIを追加
- セッション管理機能を追加
```
