# touhou_music_discover
東方同人音楽流通の楽曲を収集するWebアプリ

## 使い方

### 初回の環境構築

Dockerイメージを作成して、 `bin/setup` を実行する。

```shell
make init
```

### bundle install

```shell
make bundle
```

### DB関連

- DB init
  ```shell
  make dbinit
  ```

- DB console
  ```shell
  make dbconsole
  ```

- DB migrate
  ```shell
  make migrate
  ```

- DB rollback
  ```shell
  make rollback
  ```

- DB seed
  ```shell
  make dbseed
  ```

### サーバーの起動

```shell
make server
```

実行すると http://localhost:3000 でアクセスできる。

### コンソールの起動

```shell
make console
```

- sandbox
  ```shell
  make console-sandbox
  ```

### テストの実行

````shell
make minitest
````

### Rubocop

- 実行
    ```shell
    make rubocop
    ```

### Railsコマンド

```shell
docker compose run --rm web bin/rails -T
```

### コンテナ内で作業する

```shell
$ make bash
docker compose run --rm web bash
Creating touhou_music_discover_web_run ... done
root@ea9f1bc59441:/app# bin/rails --version
Rails 6.1.4
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
  docker compose run --rm web bin/rails spotify:fetch_touhou_albums
  ```

- Spotify Audio Features情報を取得
  ```shell
  docker compose run --rm web bin/rails spotify:fetch_audio_features
  ```

- Spotify SpotifyAlbumの情報を更新
  ```shell
  docker compose run --rm web bin/rails spotify:update_spotify_albums
  ```

- Spotify SpotifyTrackの情報を更新
  ```shell
  docker compose run --rm web bin/rails spotify:update_spotify_tracks
  ```

### AppleMusic

`APPLE_MUSIC_SECRET_KEY`と`APPLE_MUSIC_TEAM_ID`と`APPLE_MUSIC_MUSIC_ID`を設定する

- AppleMusic MasterArtistからAppleMusicのアーティスト情報を取得
  - `make dbseed`を行っておく
  ```shell
  docker compose run --rm web bin/rails apple_music:fetch_apple_music_artist_from_master_artists
  ```

- AppleMusic アーティストに紐づくアルバム情報を取得
  ```shell
  docker compose run --rm web bin/rails apple_music:fetch_artist_albums
  ```

- AppleMusic アルバムに紐づくトラック情報を取得
  ```shell
  docker compose run --rm web bin/rails apple_music:fetch_album_tracks
  ```

- AppleMusic ISRCからトラック情報を取得し、アルバム情報を取得
  ```shell
  docker compose run --rm web bin/rails apple_music:fetch_tracks_by_isrc
  ```

- AppleMusic Various Artistsのアルバムとトラックを取得
  ```shell
  docker compose run --rm web bin/rails apple_music:fetch_various_artists_albums
  ```

- AppleMusic AppleMusicAlbumの情報を更新
  ```shell
  docker compose run --rm web bin/rails apple_music:update_apple_music_albums
  ```

- AppleMusic AppleMusicTrackの情報を更新
  ```shell
  docker compose run --rm web bin/rails apple_music:update_apple_music_tracks
  ```

### YouTube Music

- YouTube Music アルバムを検索してアルバム情報を取得
  ```shell
  docker compose run --rm web bin/rails ytmusic:search_albums_and_save
  ```

- YouTube Music アルバム情報からトラック情報を取得
  ```shell
  docker compose run --rm web bin/rails ytmusic:album_tracks_save
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
  docker compose run --rm web bin/rails ytmusic:fetch_albums
  ```

- YouTube Music アルバムとトラック情報を更新
  ```shell
  docker compose run --rm web bin/rails ytmusic:update_album_and_tracks
  ```

### LINE MUSIC

- LINE MUSIC アルバムを検索して情報を取得
  ```shell
  docker compose run --rm web bin/rails line_music:search_albums_and_save
  ```

- LINE MUSIC アルバムのトラック情報を取得
  ```shell
  docker compose run --rm web bin/rails line_music:album_tracks_find_and_save
  ```

- LINE MUSIC アルバム情報を取得
  ```shell
  docker compose run --rm web bin/rails line_music:fetch_albums
  ```

- LINE MUSIC LineMusicAlbumの情報を更新
  ```shell
  docker compose run --rm web bin/rails line_music:update_line_music_albums
  ```

- LINE MUSIC LineMusicTrackの情報を更新
  ```shell
  docker compose run --rm web bin/rails line_music:update_line_music_tracks
  ```

### 共通

- 外部から`touhou_music_with_original_songs.tsv`を取得し原曲紐付けを行う
  ```shell
  docker compose run --rm web bin/rails touhou_music_discover:import:fetch_touhou_music_with_original_songs
  ```

- 原曲付きリストを`./tmp/touhou_music_with_original_songs.tsv`に出力
  ```shell
  docker compose run --rm web bin/rails touhou_music_discover:export:touhou_music_with_original_songs
  ```

- 原曲付きリストを`./tmp/touhou_music_with_original_songs.tsv`を読み込み原曲紐付けを行う
  ```shell
  docker compose run --rm web bin/rails touhou_music_discover:import:touhou_music_with_original_songs
  ```

- 東方同人音楽流通 配信曲リスト出力
  ```shell
  docker compose run --rm web bin/rails touhou_music_discover:export:touhou_music
  ```

- 東方同人音楽流通 配信曲リストスリム版出力
  ```shell
  docker compose run --rm web bin/rails touhou_music_discover:export:touhou_music_slim
  ```

- 東方同人音楽流通 配信アルバムリスト出力
  ```shell
  docker compose run --rm web bin/rails touhou_music_discover:export:touhou_music_album_only
  ```

- Algolia向けのJSON出力
  ```shell
  docker compose run --rm web bin/rails touhou_music_discover:export:for_algolia
  ```

- 東方同人音楽流通 東方サブスクランダム選曲アプリ用JSON出力
  ```shell
  docker compose run --rm web bin/rails touhou_music_discover:export:to_random_touhou_music
  ```

- 原曲情報を見て、is_touhouフラグを変更する
  ```shell
  docker compose run --rm web bin/rails touhou_music_discover:change_is_touhou_flag
  ```

- アルバムにサークルを紐付ける
  ```shell
  docker compose run --rm web bin/rails touhou_music_discover:associate_album_with_circle
  ```

- 原曲紐づけがないアルバム一覧
  ```shell
  docker compose run --rm web bin/rails touhou_music_discover:export:missing_original_songs_albums
  ```