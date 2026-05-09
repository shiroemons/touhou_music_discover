# touhou_music_discover
東方同人音楽流通の楽曲を収集するWebアプリ

## 開発環境のセットアップ

### 前提条件

- [devbox](https://www.jetify.com/devbox) がインストールされていること
- [direnv](https://direnv.net/) がインストールされていること（推奨）

### 初回セットアップ

1. devbox環境に入る
   ```shell
   devbox shell
   ```

2. 依存パッケージをインストール
   ```shell
   make setup
   ```

3. データベースの初期化
   ```shell
   make dbinit
   ```

4. マスターデータの投入
   ```shell
   make dbseed
   ```

### サーバーの起動

全サービス（PostgreSQL, Redis, Rails, Solid Queue worker, JS/CSS）をまとめて起動:

```shell
make tui
```

バックグラウンドで起動する場合:

```shell
make up
```

実行すると http://localhost:3000 でアクセスできる。

管理画面のアクション処理はSolid Queue経由の非同期ジョブとして実行される。`make up` / `make tui` では `jobs` サービスも起動するため、管理画面のアクションを動かす場合はRailsだけでなく `jobs` も起動していることを確認する。

サービス状態の確認:

```shell
make status
```

Solid Queueのジョブ実行状況を確認:

```shell
devbox run -- bin/rails runner 'SolidQueue::Job.order(id: :desc).limit(5).each { |job| p [job.id, job.queue_name, job.class_name, job.finished_at, job.created_at] }'
```

サービスの停止:

```shell
make down
```

### bundle install

```shell
make bundle
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
  make dbinit
  ```

- DBコンソール
  ```shell
  make dbconsole
  ```

- DBマイグレーション
  ```shell
  make migrate
  ```

- DBロールバック
  ```shell
  make rollback
  ```

- DBシード
  ```shell
  make dbseed
  ```

- DBバックアップ
  ```shell
  make db-dump
  ```

- DBリストア
  ```shell
  make db-restore
  ```

### コンソールの起動

```shell
make console
```

- sandbox
  ```shell
  make console-sandbox
  ```

### テストの実行

```shell
make minitest
```

### Rubocop

- 実行
  ```shell
  make rubocop
  ```

- 自動修正
  ```shell
  make rubocop-autocorrect
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

```shell
make help
```

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
   http://127.0.0.1:3000/auth/spotify/callback
   ```

2. ブラウザで `http://127.0.0.1:3000` にアクセス

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
  - `make dbseed`を行っておく
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

### 共通

- 外部から`touhou_music_with_original_songs.tsv`を取得し原曲紐付けを行う
  ```shell
  make fetch-touhou-music-with-original-songs
  ```

- 原曲付きリストを`./tmp/touhou_music_with_original_songs.tsv`に出力
  ```shell
  make export-touhou-music-with-original-songs
  ```

- 原曲付きリストを`./tmp/touhou_music_with_original_songs.tsv`を読み込み原曲紐付けを行う
  ```shell
  make import-touhou-music-with-original-songs
  ```

- 東方同人音楽流通 配信曲リスト出力
  ```shell
  make export-touhou-music
  ```

- 東方同人音楽流通 配信曲リストスリム版出力
  ```shell
  make export-touhou-music-slim
  ```

- 東方同人音楽流通 配信アルバムリスト出力
  ```shell
  make export-touhou-music-album-only
  ```

- Algolia向けのJSON出力
  ```shell
  make export-for-algolia
  ```

- 東方同人音楽流通 東方サブスクランダム選曲アプリ用JSON出力
  ```shell
  make export-to-random-touhou-music
  ```

- 原曲情報を見て、is_touhouフラグを変更する
  ```shell
  make change-is-touhou-flag
  ```

- アルバムにサークルを紐付ける
  ```shell
  make associate-album-with-circle
  ```

- 原曲紐づけがないアルバム一覧
  ```shell
  make export-missing-original-songs-albums
  ```

## Docker環境（レガシー）

Docker環境も引き続き利用可能です。全てのコマンドに `docker-` プレフィックスを付けて使用します。

### 初回の環境構築

```shell
make docker-init
```

### サーバーの起動

```shell
make docker-server
```

### その他のDockerコマンド

```shell
make docker-console      # Railsコンソール
make docker-migrate      # マイグレーション
make docker-minitest     # テスト実行
make docker-rubocop      # Rubocop
make docker-bash         # コンテナ内のbash
```

全てのコマンドは `make help` で確認できます。
