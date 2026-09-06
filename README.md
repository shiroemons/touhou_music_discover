# touhou_music_discover
東方同人音楽流通の楽曲を収集するWebアプリ

## 開発環境のセットアップ

### 前提条件

- [devbox](https://www.jetify.com/devbox) がインストールされていること
- [mise](https://mise.jdx.dev/) がインストールされていること
- [direnv](https://direnv.net/) がインストールされていること（推奨）

### 初回セットアップ

1. Taskをインストール
   ```shell
   mise install
   ```

2. devbox環境に入る
   ```shell
   devbox shell
   ```

3. 依存パッケージをインストール
   ```shell
   task setup
   ```

4. データベースの初期化
   ```shell
   task db:init
   ```

5. マスターデータの投入
   ```shell
   task db:seed
   ```

### サーバーの起動

全サービス（PostgreSQL, Redis, Rails, Solid Queue worker, JS/CSS）をまとめて起動:

```shell
task tui
```

バックグラウンドで起動する場合:

```shell
task up
```

通常は http://127.0.0.1:3000 でアクセスできる。3000番ポートが使用中の場合は、次に空いているポートを自動的に選択する。実際のアクセス先は `task up` 完了時、または `task health` の `URL` 行で確認できる。

起動ポートを指定する場合は、`PORT` に優先ポートを設定する。指定したポートも使用中なら、そこから次の空きポートを選択する。

```shell
PORT=3001 task up
```

SpotifyがOAuthのリダイレクトURIに `localhost` を許可していないため開発環境ではループバックIPを使用しており、`localhost` でアクセスした場合は自動的に `127.0.0.1` へリダイレクトされる。

管理画面のアクション処理はSolid Queue経由の非同期ジョブとして実行される。`task up` / `task tui` では `jobs` サービスも起動するため、管理画面のアクションを動かす場合はRailsだけでなく `jobs` も起動していることを確認する。

サービス状態の確認:

```shell
task status
```

Solid Queueのジョブ実行状況を確認:

```shell
devbox run -- bin/rails runner 'SolidQueue::Job.order(id: :desc).limit(5).each { |job| p [job.id, job.queue_name, job.class_name, job.finished_at, job.created_at] }'
```

サービスの停止:

```shell
task down
```

### bundle install

```shell
task bundle
```

### DB関連

このアプリはRails本体用の `primary` DBと、Solid Queue用の `queue` DBを使う。ローカル環境では以下のDBが作成される。

- `touhou_music_discover_development`
- `touhou_music_discover_development_queue`
- `touhou_music_discover_test`
- `touhou_music_discover_test_queue`

Solid Queueのスキーマは `db/queue_schema.rb` で管理される。

- DB初期化（drop & setup）
  ```shell
  task db:init
  ```

- DBコンソール
  ```shell
  task db:console
  ```

- DBマイグレーション
  ```shell
  task db:migrate
  ```

- DBロールバック
  ```shell
  task db:rollback
  ```

- DBシード
  ```shell
  task db:seed
  ```

- DBバックアップ
  ```shell
  task db:backup
  ```
  `tmp/data/touhou_music_discover-YYYYMMDD-HHMMSS.bak` にgzip圧縮されたカスタム形式で保存される。

- DBリストア
  ```shell
  task db:restore
  ```
  `BACKUP_FILE`を指定しない場合は、`tmp/data`内の最新の日付付きバックアップを使用する。
  ```shell
  BACKUP_FILE=tmp/data/touhou_music_discover-20260811-175418.bak task db:restore
  ```

### コンソールの起動

```shell
task console
```

- sandbox
  ```shell
  task console:sandbox
  ```

### テストの実行

```shell
task test
```

### Rubocop

- 実行
  ```shell
  task lint
  ```

- 自動修正
  ```shell
  task lint:fix
  ```

### Railsコマンド

devboxシェル内で直接実行:

```shell
devbox shell
bin/rails -T
```

または:

```shell
devbox run -- bin/rails -T
```

### 利用可能なコマンド一覧

全タスクの一覧だけを表示する場合:

```shell
task --list
```

| 分類 | コマンド | 用途 |
| --- | --- | --- |
| 基本 | `task` / `task help` | タスク一覧を表示 |
| 基本 | `task setup` | devbox環境を初期化（bundle + yarn） |
| 基本 | `task shell` | devboxシェルを起動 |
| 基本 | `task versions` | Ruby / PostgreSQL / Redis / Node.js / Yarnのバージョンを表示 |
| 基本 | `task bundle` | bundle installを実行 |
| 基本 | `task server` | Railsサーバーを起動 |
| 基本 | `task console` | Railsコンソールを起動 |
| 基本 | `task console:sandbox` | sandbox付きRailsコンソールを起動 |
| サービス | `task up` | 全サービスをバックグラウンドで起動 |
| サービス | `task tui` | 全サービスをTUIモードで起動 |
| サービス | `task logs` | Railsサーバーのログを表示 |
| サービス | `task down` | devboxサービスを停止 |
| サービス | `task restart` | サービスを停止・復旧して再起動 |
| サービス | `task status` / `task ps` | devboxサービスの状態を表示 |
| サービス | `task health` / `task doctor` | サービス、待受ポート、HTTP応答を確認 |
| サービス | `task recover` | サービスを停止して復旧起動（孤児プロセスは停止しない） |
| サービス | `task recover-force` | 孤児プロセスを停止してサービスを復旧起動 |
| サービス | `task kill-orphan-ports` | Railsの起動ポート / 5432 / 6379の孤児プロセスを停止 |
| DB | `task db:init` | DBをdrop & setupで初期化 |
| DB | `task db:console` | DBコンソールを起動 |
| DB | `task db:migrate` | DBマイグレーションを実行 |
| DB | `task db:migrate:redo` | 直前のマイグレーションをやり直し |
| DB | `task db:rollback` | DBマイグレーションをロールバック |
| DB | `task db:seed` | マスターデータを投入 |
| DB | `task db:backup` | gzip圧縮した日付付きファイルへDBをバックアップ |
| DB | `task db:restore` | 最新または指定したDBバックアップをリストア |
| データ | `task data:upsert-originals` | 原作・原曲データをupsert |
| 品質 | `task test` | テストを実行 |
| 品質 | `task lint` | Rubocopを実行 |
| 品質 | `task lint:fix` | Rubocopを自動修正 |
| 品質 | `task lint:fix:all` | Rubocopを全範囲で自動修正 |
| 入力 | `task import:fetch-touhou-music` | 外部から原曲紐付けデータを取得して反映 |
| 入力 | `task import:touhou-music-with-original-songs` | 原曲付きリストを読み込んで反映 |
| 出力 | `task export:touhou-music-with-original-songs` | 原曲付きリストを出力 |
| 出力 | `task export:touhou-music` | 配信曲リストを出力 |
| 出力 | `task export:touhou-music-slim` | 配信曲リストのスリム版を出力 |
| 出力 | `task export:touhou-music-album-only` | 配信アルバムリストを出力 |
| 出力 | `task export:for-algolia` | Algolia向けJSONを出力 |
| 出力 | `task export:to-random-touhou-music` | 東方サブスクランダム選曲アプリ向けJSONを出力 |
| 出力 | `task export:missing-original-songs-albums` | 原曲紐付けがないアルバム一覧を出力 |
| 出力 | `task export:spotify` | Spotify向けデータを出力 |
| 出力 | `task export:all` | すべてのエクスポートファイルを一括出力 |
| データ更新 | `task change:is-touhou-flag` | 原曲情報をもとに`is_touhou`を更新 |
| データ更新 | `task associate:album-with-circle` | アルバムとサークルを紐付け |

### Cloudflare向けカタログsnapshot

Cloudflare側へ渡す正式な同期データは、既存のTSV／Algolia出力ではなく、品質ゲート付きのversioned JSONL snapshotを使用します。外部APIは呼び出さず、Rails DBの保存済みデータだけを読み取ります。

```shell
OUTPUT_DIR=/path/to/catalog-snapshots devbox run -- bin/rails touhou_music_discover:catalog:preflight
OUTPUT_DIR=/path/to/catalog-snapshots devbox run -- bin/rails touhou_music_discover:catalog:export
```

`preflight`がエラーを検出した場合、snapshotは生成されず、`OUTPUT_DIR/reports/`に診断レポートが出力されます。現在のDBにはLINE MUSICのalbum／track親紐付け不一致があるため、修正が完了するまで`export`は停止します。

## 情報収集

- ローカル環境
```shell
cp .env.development.local.example .env.development.local
```

### Spotify

`SPOTIFY_CLIENT_ID`と`SPOTIFY_CLIENT_SECRET`を設定する

#### Spotify OAuth認証

Spotifyはセキュリティ強化のため、HTTPのリダイレクトURIおよび`localhost`を使用したURIを廃止しました（2025年11月27日に完全廃止予定）。
詳細は[公式ブログ](https://developer.spotify.com/blog/2025-02-12-increasing-the-security-requirements-for-integrating-with-spotify)および[移行ガイド](https://developer.spotify.com/documentation/web-api/tutorials/migration-insecure-redirect-uri)を参照してください。

ただし、ループバックIPアドレス（`127.0.0.1`）は例外として許可されています。

1. [Spotify Developer Dashboard](https://developer.spotify.com/dashboard)でアプリの設定を開き、Redirect URIに以下を追加
   ```
   http://127.0.0.1:<起動したポート>/auth/spotify/callback
   ```

2. `task health` の `URL` 行に表示された `http://127.0.0.1:<起動したポート>` にブラウザでアクセス

**注意**: `localhost`ではなく`127.0.0.1`を使用してください。

- Spotify label:東方同人音楽流通 のアルバムとトラックを年代ごとに取得
  ```shell
  devbox run -- bin/rails spotify:fetch_touhou_albums
  ```

- Spotify Audio Features情報を取得
  ```shell
  devbox run -- bin/rails spotify:fetch_audio_features
  ```

- Spotify SpotifyAlbumの情報を更新
  ```shell
  devbox run -- bin/rails spotify:update_spotify_albums
  ```

- Spotify SpotifyTrackの情報を更新
  ```shell
  devbox run -- bin/rails spotify:update_spotify_tracks
  ```

### AppleMusic

`APPLE_MUSIC_SECRET_KEY`と`APPLE_MUSIC_TEAM_ID`と`APPLE_MUSIC_MUSIC_ID`を設定する

- AppleMusic MasterArtistからAppleMusicのアーティスト情報を取得
  - `task db:seed`を行っておく
  ```shell
  devbox run -- bin/rails apple_music:fetch_apple_music_artist_from_master_artists
  ```

- AppleMusic アーティストに紐づくアルバム情報を取得
  ```shell
  devbox run -- bin/rails apple_music:fetch_artist_albums
  ```

- AppleMusic アルバムに紐づくトラック情報を取得
  ```shell
  devbox run -- bin/rails apple_music:fetch_album_tracks
  ```

- AppleMusic ISRCからトラック情報を取得し、アルバム情報を取得
  ```shell
  devbox run -- bin/rails apple_music:fetch_tracks_by_isrc
  ```

- AppleMusic Various Artistsのアルバムとトラックを取得
  ```shell
  devbox run -- bin/rails apple_music:fetch_various_artists_albums
  ```

- AppleMusic AppleMusicAlbumの情報を更新
  ```shell
  devbox run -- bin/rails apple_music:update_apple_music_albums
  ```

- AppleMusic AppleMusicTrackの情報を更新
  ```shell
  devbox run -- bin/rails apple_music:update_apple_music_tracks
  ```

### YouTube Music

- YouTube Music アルバムを検索してアルバム情報を取得
  ```shell
  devbox run -- bin/rails ytmusic:search_albums_and_save
  ```

- YouTube Music アルバム情報からトラック情報を取得
  ```shell
  devbox run -- bin/rails ytmusic:album_tracks_save
  ```

- 取得できなかったアルバムを検索
  ```ruby
  # キーワードにサークル名やアルバム名を入れる
  result = YTMusic::Album.search("キーワード")
  result.data[:albums].each do |a|
    puts "#{a.title}\t#{a.browse_id}"
  end;nil
  ```

- YouTube Music アルバム情報を取得
  ```shell
  devbox run -- bin/rails ytmusic:fetch_albums
  ```

- YouTube Music アルバムとトラック情報を更新
  ```shell
  devbox run -- bin/rails ytmusic:update_album_and_tracks
  ```

### LINE MUSIC

- LINE MUSIC アルバムを検索して情報を取得
  ```shell
  devbox run -- bin/rails line_music:search_albums_and_save
  ```

- LINE MUSIC アルバムのトラック情報を取得
  ```shell
  devbox run -- bin/rails line_music:album_tracks_find_and_save
  ```

- LINE MUSIC アルバム情報を取得
  ```shell
  devbox run -- bin/rails line_music:fetch_albums
  ```

- LINE MUSIC LineMusicAlbumの情報を更新
  ```shell
  devbox run -- bin/rails line_music:update_line_music_albums
  ```

- LINE MUSIC LineMusicTrackの情報を更新
  ```shell
  devbox run -- bin/rails line_music:update_line_music_tracks
  ```

- LINE MUSICトラックのcanonical親不整合を確認・修復（既定はdry-run）
  ```shell
  devbox run -- bin/rails line_music:repair_track_parent_mismatches
  APPLY=1 devbox run -- bin/rails line_music:repair_track_parent_mismatches
  ```

### 共通

- 外部から`touhou_music_with_original_songs.tsv`を取得し原曲紐付けを行う
  ```shell
  task import:fetch-touhou-music
  ```

- 原曲付きリストを`./tmp/touhou_music_with_original_songs.tsv`に出力
  ```shell
  task export:touhou-music-with-original-songs
  ```

- 原曲付きリストを`./tmp/touhou_music_with_original_songs.tsv`を読み込み原曲紐付けを行う
  ```shell
  task import:touhou-music-with-original-songs
  ```

- 東方同人音楽流通 配信曲リスト出力
  ```shell
  task export:touhou-music
  ```

- 東方同人音楽流通 配信曲リストスリム版出力
  ```shell
  task export:touhou-music-slim
  ```

- 東方同人音楽流通 配信アルバムリスト出力
  ```shell
  task export:touhou-music-album-only
  ```

- Algolia向けのJSON出力
  ```shell
  task export:for-algolia
  ```

  通常は直近1か月以内に更新されたアルバムを出力します。未反映の古いアルバムを追加投入する場合は、JANコードをカンマ区切りで指定します。指定時は更新日条件を適用せず、対象アルバムの全トラックを出力します。

  ```shell
  JAN_CODES=4582736137602 devbox run export:for_algolia
  JAN_CODES=4582736137602,4582736138272 devbox run export:for_algolia
  ```

  全アルバムを出力する場合は`FULL_EXPORT=1`を指定できます。既存の出力先を保持したまま追加用ファイルを作る場合は`ALGOLIA_OUTPUT_DIR`を指定してください。

  ```shell
  FULL_EXPORT=1 ALGOLIA_OUTPUT_DIR=tmp/algolia/full devbox run export:for_algolia
  ```

  管理画面からLINE MUSICアルバムの置換を実行した場合は、DBトランザクションの完了後に対象アルバム1件分の `touhou_music_line_music_for_algolia.json` を自動出力します。出力先は `ALGOLIA_OUTPUT_DIR`（未指定時は `tmp/algolia`）です。出力に失敗してもアルバム置換自体は維持され、管理画面の結果に警告を表示します。

- 東方同人音楽流通 東方サブスクランダム選曲アプリ用JSON出力
  ```shell
  task export:to-random-touhou-music
  ```

- 原曲情報を見て、is_touhouフラグを変更する
  ```shell
  task change:is-touhou-flag
  ```

- アルバムにサークルを紐付ける
  ```shell
  task associate:album-with-circle
  ```

- 原曲紐づけがないアルバム一覧
  ```shell
  task export:missing-original-songs-albums
  ```
