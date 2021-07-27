# touhou_music_discover
東方同人音楽流通の楽曲を収集するWebアプリ

## Spotify

### ローカル環境

- `SPOTIFY_CLIENT_ID`と`SPOTIFY_CLIENT_SECRET`を設定する
    ```shell
    cp .env.development.local.example .env.development.local
    ```

#### 情報収集

- Spotify MasterArtistからアーティスト情報を取得
    ```shell
    docker-compose run --rm web bundle exec rails spotify:master_artist_fetch
    ```

- Spotify アーティストに紐づくアルバム情報とトラック情報を取得
    ```shell
    docker-compose run --rm web bundle exec rails spotify:artists_album_and_tracks_fetch
    ```

- Spotify SpotifyTrackからアーティスト情報を取得
    ```shell
    docker-compose run --rm web bundle exec rails spotify:spotify_track_artist_fetch
    ```
