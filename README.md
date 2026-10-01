# touhou_music_discover
東方同人音楽流通の楽曲を収集するWebアプリ

## 開発環境のセットアップ

### 前提条件

- [devbox](https://www.jetify.com/devbox) がインストールされていること
- [mise](https://mise.jdx.dev/) がインストールされていること
- [direnv](https://direnv.net/) がインストールされていること（推奨）

### 初回セットアップ

1. justをインストール
   ```shell
   mise install
   ```

2. devbox環境に入る
   ```shell
   devbox shell
   ```

3. 依存パッケージをインストール
   ```shell
   just setup
   ```

4. データベースの初期化
   ```shell
   just db init
   ```

5. マスターデータの投入
   ```shell
   just db seed
   ```

### サーバーの起動

全サービス（PostgreSQL, Redis, Rails, Solid Queue worker, JS/CSS）をまとめて起動:

```shell
just tui
```

バックグラウンドで起動する場合:

```shell
just up
```

通常は http://127.0.0.1:3000 でアクセスできる。3000番ポートが使用中の場合は、次に空いているポートを自動的に選択する。実際のアクセス先は `just up` 完了時、または `just health` の `URL` 行で確認できる。

開発サーバーの bind は既定で `127.0.0.1`。管理認証を無効にする場合は開発環境で `ADMIN_AUTH_DISABLED=true` を明示する（`just up` と Docker Compose は開発用設定を渡す）。Docker Compose はコンテナ内からアクセスできるよう `RAILS_BIND_ADDRESS=0.0.0.0` を設定する。本番環境では `ADMIN_USERNAME`、`ADMIN_PASSWORD`、`APP_HOST` が必須。

起動ポートを指定する場合は、`PORT` に優先ポートを設定する。指定したポートも使用中なら、そこから次の空きポートを選択する。

`bin/dev-server` は追加引数を受け付けない。bind は `RAILS_BIND_ADDRESS`、環境は `RAILS_ENV`、ポートは `PORT` で指定する。

```shell
PORT=3001 just up
```

SpotifyがOAuthのリダイレクトURIに `localhost` を許可していないため開発環境ではループバックIPを使用しており、`localhost` でアクセスした場合は自動的に `127.0.0.1` へリダイレクトされる。

### ワークツリーで並行開発する

[git-wt](https://github.com/k1LoW/git-wt) で作ったワークツリーごとに、Rails / PostgreSQL / Redis / process-compose を本体と重ならないポートで起動できる。DBもワークツリーごとに専用のPostgreSQLを持ち、作成時に本体の開発DBをコピーする。

最初に一度だけ、本体のチェックアウトで git wt のフックを設定する（`.git/config` に書き込む）:

```shell
just worktree config
```

以降は `git wt <ブランチ名>` でワークツリーを作ると、次の処理が自動で走る（通常 20 秒前後）。

- 34000〜35999 から 10 ポート単位のブロックを割り当て、`.worktree.env` にポートを書き出す
  - ブロックの先頭が Rails、+1 が PostgreSQL、+2 が Redis、+3 が process-compose。Rails は隣のブロックにずれないよう固定ポートで起動する
  - 割り当ての台帳はユーザー単位（`~/.local/state/worktree-ports/registry.tsv`）で、他のワークツリーや、同じ仕組みを使う他のリポジトリとも重ならない。割り当て時に使用中のポートも避ける
  - 34000〜35999 は、他のリポジトリが使うポート（1025〜8090 / 15432 / 18080 / 28080 / 55432 など）や macOS の一時ポート（49152 以降）と重ならない範囲として選んでいる
- 本体の bundle と node_modules を複製（APFS のクローンなので容量はほぼ増えない）して依存を入れる
- ワークツリー専用の PostgreSQL を初期化し、本体の開発DBをコピーする。本体の PostgreSQL が停止中なら一時的に起動し、コピー後に停止する
- Solid Queue のキューDBは、ジョブの二重実行を防ぐためコピーせず空で作成する

ワークツリー内では、本体と同じく `just up` / `just health` / `just test` などがそのまま使える。`.worktree.env` は devbox の init_hook と justfile が読み込み、環境変数の `PORT` / `PGPORT` より優先する。コピー元のDBは本体の開発DBのままで、ブランチに未適用のマイグレーションがあればセットアップの最後に案内を表示する。

セッション Cookie の名前もワークツリーごとに分けている（`.worktree.env` の `SESSION_COOKIE_KEY`）。Cookie はポートで分離されないため、分けないと 127.0.0.1 上の本体とワークツリーがログイン状態を上書きし合う。

Spotify のログイン情報はワークツリーごとの Redis に保存されるため、ログインが必要な機能はワークツリーのポートでログインし直す。このとき redirect URI は `http://127.0.0.1:<Railsのポート>/auth/spotify/callback` になる。Spotify の仕様ではループバックアドレスはポートなしで登録できるはずだが、Developer Dashboard は「This redirect URI is not secure」として受け付けない。そのため、本体の `:3000` に加えて、ワークツリー用に `:34000` / `:34010` / `:34020` / `:34030` / `:34040` の 5 つを登録している。これより大きいポートが割り当てられた場合はセットアップの最後に注意を表示する。ワークツリーを同時に 6 つ以上使う場合は、Dashboard に URI を追加する。

`git wt -d <ブランチ名>` で削除すると、削除前にそのワークツリーのサービスを停止し、ポートの割り当てを解放する。

作成・作業・片付けの詳しい手順は、Claude Code と Codex が共通で使うスキル [`.agents/skills/worktree/SKILL.md`](.agents/skills/worktree/SKILL.md) にまとめている（Claude Code からは `.claude/skills/worktree` のシンボリックリンク経由で読む）。

| コマンド | 用途 |
| --- | --- |
| `just worktree config` | git wt の作成・削除フックと、コピー除外設定（`.devbox/` / `tmp/` / `log/` など）を設定 |
| `just worktree setup` | 現在のワークツリーをセットアップ（Claude Code など git wt 以外で作ったワークツリー用。再実行しても既存のDBは保持する） |
| `just worktree db-copy` | 現在のワークツリーの開発DBを本体の開発DBで置き換える |
| `just worktree list` | ワークツリーごとの割り当てポートと Rails の応答状況を一覧表示 |

管理画面のアクション処理はSolid Queue経由の非同期ジョブとして実行される。`just up` / `just tui` では `jobs` サービスも起動するため、管理画面のアクションを動かす場合はRailsだけでなく `jobs` も起動していることを確認する。

サービス状態の確認:

```shell
just status
```

Solid Queueのジョブ実行状況を確認:

```shell
devbox run -- bin/rails runner 'SolidQueue::Job.order(id: :desc).limit(5).each { |job| p [job.id, job.queue_name, job.class_name, job.finished_at, job.created_at] }'
```

サービスの停止:

```shell
just down
```

### bundle install

```shell
just bundle
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
  just db init
  ```

- DBコンソール
  ```shell
  just db console
  ```

- DBマイグレーション
  ```shell
  just db migrate
  ```

- DBロールバック
  ```shell
  just db rollback
  ```

- DBシード
  ```shell
  just db seed
  ```

- DBバックアップ
  ```shell
  just db backup
  ```
  `tmp/data/touhou_music_discover-YYYYMMDD-HHMMSS.bak` にgzip圧縮されたカスタム形式で保存される。

- DBリストア
  ```shell
  just db restore
  ```
  `BACKUP_FILE`を指定しない場合は、`tmp/data`内の最新の日付付きバックアップを使用する。
  ```shell
  BACKUP_FILE=tmp/data/touhou_music_discover-20260811-175418.bak just db restore
  ```
  復元先の既定値は `touhou_music_discover_development`。検証用DBに復元する場合は `RESTORE_DB` を指定する。
  指定できるのは既定の開発DB、または `touhou_music_discover_restore_check_` で始まる英数字と `_` のみのDB名。
  接続文字列・URIや、それ以外のDB名は受け付けない。
  実行時に接続先（`PGHOST` / `PGPORT`）・復元先DB・バックアップファイル・成功/失敗を表示し、途中で失敗した場合は復元開始前の状態に戻す。
  ```shell
  RESTORE_DB=touhou_music_discover_restore_check_example BACKUP_FILE=tmp/data/touhou_music_discover-20260811-175418.bak just db restore
  ```

### コンソールの起動

```shell
just console
```

- sandbox
  ```shell
  just console sandbox
  ```

### テストの実行

```shell
just test
```

### Rubocop

- 実行
  ```shell
  just lint
  ```

- 自動修正
  ```shell
  just lint fix
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
just --list --list-submodules
```

`db` / `worktree` / `lint` / `export` などの名前空間は `just/` 配下のモジュールに分けている。`just db migrate` のように空白区切りで実行する（`just db::migrate` と書いても同じ）。

| 分類 | コマンド | 用途 |
| --- | --- | --- |
| 基本 | `just` / `just help` | タスク一覧を表示 |
| 基本 | `just setup` | devbox環境を初期化（bundle + yarn） |
| 基本 | `just shell` | devboxシェルを起動 |
| 基本 | `just versions` | Ruby / PostgreSQL / Redis / Node.js / Yarnのバージョンを表示 |
| 基本 | `just bundle` | bundle installを実行 |
| 基本 | `just server` | Railsサーバーを起動 |
| 基本 | `just console` | Railsコンソールを起動 |
| 基本 | `just console sandbox` | sandbox付きRailsコンソールを起動 |
| サービス | `just up` | 全サービスをバックグラウンドで起動 |
| サービス | `just tui` | 全サービスをTUIモードで起動 |
| サービス | `just logs` | Railsサーバーのログを表示 |
| サービス | `just down` | devboxサービスを停止 |
| サービス | `just restart` | サービスを停止・復旧して再起動 |
| サービス | `just status` / `just ps` | devboxサービスの状態を表示 |
| サービス | `just health` / `just doctor` | サービス、待受ポート、HTTP応答を確認 |
| サービス | `just recover` | サービスを停止して復旧起動（孤児プロセスは停止しない） |
| サービス | `just recover-force` | 孤児プロセスを停止してサービスを復旧起動 |
| サービス | `just kill-orphan-ports` | Railsの起動ポート / PostgreSQL / Redisの孤児プロセスを停止 |
| DB | `just db init` | DBをdrop & setupで初期化 |
| DB | `just db console` | DBコンソールを起動 |
| DB | `just db migrate` | DBマイグレーションを実行 |
| DB | `just db migrate-redo` | 直前のマイグレーションをやり直し |
| DB | `just db rollback` | DBマイグレーションをロールバック |
| DB | `just db seed` | マスターデータを投入 |
| DB | `just db backup` | gzip圧縮した日付付きファイルへDBをバックアップ |
| DB | `just db restore` | 最新または指定したDBバックアップをリストア |
| ワークツリー | `just worktree config` | git wt の作成・削除フックを設定 |
| ワークツリー | `just worktree setup` | 現在のワークツリーにポートを割り当て、本体の開発DBをコピー |
| ワークツリー | `just worktree db-copy` | ワークツリーの開発DBを本体の開発DBで置き換える |
| ワークツリー | `just worktree list` | ワークツリーごとの割り当てポートを一覧表示 |
| データ | `just data upsert-originals` | 原作・原曲データをupsert |
| 品質 | `just test` | テストを実行 |
| 品質 | `just lint` | Rubocopを実行 |
| 品質 | `just lint fix` | Rubocopを自動修正 |
| 品質 | `just lint fix-all` | Rubocopを全範囲で自動修正 |
| 入力 | `just import fetch-touhou-music` | 外部から原曲紐付けデータを取得して反映 |
| 入力 | `just import touhou-music-with-original-songs` | 原曲付きリストを読み込んで反映 |
| 出力 | `just export touhou-music-with-original-songs` | 原曲付きリストを出力 |
| 出力 | `just export touhou-music` | 配信曲リストを出力 |
| 出力 | `just export touhou-music-slim` | 配信曲リストのスリム版を出力 |
| 出力 | `just export touhou-music-album-only` | 配信アルバムリストを出力 |
| 出力 | `just export for-algolia` | Algolia向けJSONを出力 |
| 出力 | `just export to-random-touhou-music` | 東方サブスクランダム選曲アプリ向けJSONを出力 |
| 出力 | `just export missing-original-songs-albums` | 原曲紐付けがないアルバム一覧を出力 |
| 出力 | `just export spotify` | Spotify向けデータを出力 |
| 出力 | `just export all` | すべてのエクスポートファイルを一括出力 |
| データ更新 | `just change is-touhou-flag` | 原曲情報をもとに`is_touhou`を更新 |
| データ更新 | `just associate album-with-circle` | アルバムとサークルを紐付け |

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

2. `just health` の `URL` 行に表示された `http://127.0.0.1:<起動したポート>` にブラウザでアクセス

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
  - `just db seed`を行っておく
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
  just import fetch-touhou-music
  ```

- 原曲付きリストを`./tmp/touhou_music_with_original_songs.tsv`に出力
  ```shell
  just export touhou-music-with-original-songs
  ```

- 原曲付きリストを`./tmp/touhou_music_with_original_songs.tsv`を読み込み原曲紐付けを行う
  ```shell
  just import touhou-music-with-original-songs
  ```

- 東方同人音楽流通 配信曲リスト出力
  ```shell
  just export touhou-music
  ```

- 東方同人音楽流通 配信曲リストスリム版出力
  ```shell
  just export touhou-music-slim
  ```

- 東方同人音楽流通 配信アルバムリスト出力
  ```shell
  just export touhou-music-album-only
  ```

- Algolia向けのJSON出力
  ```shell
  just export for-algolia
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
  just export to-random-touhou-music
  ```

- 原曲情報を見て、is_touhouフラグを変更する
  ```shell
  just change is-touhou-flag
  ```

- アルバムにサークルを紐付ける
  ```shell
  just associate album-with-circle
  ```

- 原曲紐づけがないアルバム一覧
  ```shell
  just export missing-original-songs-albums
  ```
