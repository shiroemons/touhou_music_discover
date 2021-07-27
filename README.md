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

## Spotify

### ローカル環境

- `SPOTIFY_CLIENT_ID`と`SPOTIFY_CLIENT_SECRET`を設定する
    ```shell
    cp .env.development.local.example .env.development.local
    ```

#### 情報収集

- Spotify MasterArtistからアーティスト情報を取得
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
