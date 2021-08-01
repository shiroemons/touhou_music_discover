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
docker-compose run --rm web bin/rails -T
```

### コンテナ内で作業する

```shell
$ make bash
docker-compose run --rm web bash
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

- Spotify MasterArtistからアーティスト情報を取得
  - `make dbseed`を行っておく
  ```shell
  docker-compose run --rm web bin/rails spotify:master_artist_fetch
  ```

- Spotify アーティストに紐づくアルバム情報とトラック情報を取得
    ```shell
    docker-compose run --rm web bin/rails spotify:artists_album_and_tracks_fetch
    ```

- Spotify SpotifyTrackからアーティスト情報を取得
    ```shell
    docker-compose run --rm web bin/rails spotify:spotify_track_artist_fetch
    ```

### AppleMusic

`APPLE_MUSIC_SECRET_KEY`と`APPLE_MUSIC_TEAM_ID`と`APPLE_MUSIC_MUSIC_ID`を設定する

- AppleMusic MasterArtistからアーティスト情報を取得
  - `make dbseed`を行っておく
  ```shell
  docker-compose run --rm web bin/rails apple_music:master_artist_fetch
  ```

- AppleMusic アーティストに紐づくアルバム情報を取得
  ```shell
  docker-compose run --rm web bin/rails apple_music:artists_album_fetch
  ```

- AppleMusic アルバムに紐づくトラック情報を取得
  ```shell
  docker-compose run --rm web bin/rails apple_music:album_tracks_fetch
  ```

- AppleMusic ISRCからトラック情報を取得し、アルバム情報を取得
  ```shell
  docker-compose run --rm web bin/rails apple_music:isrc_fetch
  ```

- AppleMusic Various Artistsのアルバムとトラックを取得
  ```shell
  docker-compose run --rm web bin/rails apple_music:various_artists_albums_fetch
  ```

### 共通

- 外部から`touhou_music_with_original_songs.tsv`を取得し原曲紐付けを行う
  ```shell
  docker-compose run --rm web bin/rails touhou_music_discover:import:fetch_touhou_music_with_original_songs
  ```

- 原曲付きリストを`./tmp/touhou_music_with_original_songs.tsv`に出力
  ```shell
  docker-compose run --rm web bin/rails touhou_music_discover:export:touhou_music_with_original_songs
  ```

- 原曲付きリストを`./tmp/touhou_music_with_original_songs.tsv`を読み込み原曲紐付けを行う
  ```shell
  docker-compose run --rm web bin/rails touhou_music_discover:import:touhou_music_with_original_songs
  ```

- 原曲情報を見て、is_touhouフラグを変更する
  ```shell
  docker-compose run --rm web bin/rails touhou_music_discover:change_is_touhou_flag
  ```