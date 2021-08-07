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

- Spotify MasterArtistからSpotifyのアーティスト情報を取得
  - `make dbseed`を行っておく
  ```shell
  docker-compose run --rm web bin/rails spotify:fetch_spotify_artist_from_master_artists
  ```

- Spotify アーティストに紐づくアルバム情報とトラック情報を取得
  ```shell
  docker-compose run --rm web bin/rails spotify:fetch_albums_and_tracks
  ```

- Spotify SpotifyTrackからアーティスト情報を取得
  ```shell
  docker-compose run --rm web bin/rails spotify:fetch_spotify_track_artist
  ```

- Spotify Audio Features情報を取得
  ```shell
  docker-compose run --rm web bin/rails spotify:fetch_audio_features
  ```

- Spotify SpotifyAlbumの情報を更新
  ```shell
  docker-compose run --rm web bin/rails spotify:update_spotify_albums
  ```

- Spotify SpotifyTrackの情報を更新
  ```shell
  docker-compose run --rm web bin/rails spotify:update_spotify_tracks
  ```

### AppleMusic

`APPLE_MUSIC_SECRET_KEY`と`APPLE_MUSIC_TEAM_ID`と`APPLE_MUSIC_MUSIC_ID`を設定する

- AppleMusic MasterArtistからAppleMusicのアーティスト情報を取得
  - `make dbseed`を行っておく
  ```shell
  docker-compose run --rm web bin/rails apple_music:fetch_apple_music_artist_from_master_artists
  ```

- AppleMusic アーティストに紐づくアルバム情報を取得
  ```shell
  docker-compose run --rm web bin/rails apple_music:fetch_artist_albums
  ```

- AppleMusic アルバムに紐づくトラック情報を取得
  ```shell
  docker-compose run --rm web bin/rails apple_music:fetch_album_tracks
  ```

- AppleMusic ISRCからトラック情報を取得し、アルバム情報を取得
  ```shell
  docker-compose run --rm web bin/rails apple_music:fetch_tracks_by_isrc
  ```

- AppleMusic Various Artistsのアルバムとトラックを取得
  ```shell
  docker-compose run --rm web bin/rails apple_music:fetch_various_artists_albums
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

- 東方同人音楽流通 配信曲リスト出力
  ```shell
  docker-compose run --rm web bin/rails touhou_music_discover:export:touhou_music
  ```

- 原曲付きリストを`./tmp/touhou_music_with_original_songs.tsv`を読み込み原曲紐付けを行う
  ```shell
  docker-compose run --rm web bin/rails touhou_music_discover:import:touhou_music_with_original_songs
  ```

- 原曲情報を見て、is_touhouフラグを変更する
  ```shell
  docker-compose run --rm web bin/rails touhou_music_discover:change_is_touhou_flag
  ```

- アルバムにサークルを紐付ける
  ```shell
  docker-compose run --rm web bin/rails touhou_music_discover:associate_album_with_circle
  ```
