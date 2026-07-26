# Spotify OAuth・プレイリスト系を SpotifyApi へ移行する設計

- Issue: #562（[Spotify移行 3/4]）
- 親 Issue: #564
- 前提 Issue: #560
- 作成日: 2026-07-26

## 1. 目的

ユーザー OAuth（OmniAuth ログイン）とプレイリスト操作を `RSpotify::*` から自前クライアント
`SpotifyApi::*` へ移行する。あわせて、移行の過程で判明した実バグを修正し、デッドコードを撤去する。

## 2. 実測で確定した前提

設計に先立ち、保存済みユーザートークンを使って実 Spotify Web API を read-only で叩き、
Issue #562 本文の前提を検証した。**Issue 本文の前提が 2 点誤っていた。**

| # | 実測結果 | 設計への影響 |
|---|---|---|
| 1 | `SpotifyApi::UserSession` / `SpotifyApi::Playlist` は実装済み・テスト 28 件付きで、**本番コードから一度も呼ばれていない**（PR #567 由来） | 主作業は新規実装ではなく呼び出し先の差し替え |
| 2 | `UserSession` の期限切れトークンのリフレッシュと Redis 書き戻しが実 API で成功。refresh_token はローテーションされなかった | トークン管理の追加実装は不要 |
| 3 | **`GET /me` は `email` と `account_id` を現在も返す** | Issue の「`email` が削除された」は誤り。`user-read-email` スコープは残す |
| 4 | **`tracks` と `items` はデュアル公開中**。`GET /playlists/{id}/tracks` と `/items` の両方が 200 を返し内容も一致。item オブジェクトは `track` と `item` の両キーを持ち、`GET /me/playlists` の item も `tracks` と `items` の両キーを持つ | Issue の「`tracks` が `items` にリネームされる」は現時点では未発生。`SpotifyApi::Playlist` の 404 限定フォールバックは保険として機能する |
| 5 | `GET /me/playlists` の item は `tracks.total` を持つが **`followers` を持たない** | follower 数は 1 プレイリストごとの追加リクエストが必要 |
| 6 | 対象ユーザーのプレイリストは 613 件、うち 612 件が `OriginalSong.title` に一致、全件 `public: true` | `index` が API を叩く経路（DB キャッシュが空のとき）の実コストは 625 リクエスト。follower を取らなければ 13 リクエスト（48 分の 1）。`playlist-read-private` は不要 |
| 7 | **`SpotifyApi::Response` に `dig` が未実装**。`Page#items` は各要素を `Response` に包むため、移行後のコードで `NoMethodError` を踏む | `dig` の追加が必要 |

注: 実測に使った検証スクリプトはリポジトリに含めない。実測値（`account_id` の値、
メールアドレス、アクセストークン）も本ドキュメントには記載しない。

### 現状の主要ファイル規模

| ファイル | 行数 | テスト |
|---|---|---|
| `app/controllers/spotify/playlists_controller.rb` | 573 | 0 件（空クラスのみ） |
| `app/services/spotify/playlist_update_service.rb` | 296 | 存在しない |
| `app/controllers/sessions_controller.rb` | 28 | 0 件（空クラスのみ） |
| `app/models/user.rb` | 19 | 0 件 |

## 3. スコープ

`E → A → B → C` の 4 フェーズを 1 本の PR で実施する。非機能改善（D）は別 Issue に切り出す。

| 群 | 内容 | 本 PR |
|---|---|---|
| E | 安全網（前後スナップショット差分 + `SpotifyApi` 経路のテスト） | 含む |
| A | OAuth 自前化 | 含む |
| B | プレイリスト系の呼び出し差し替え | 含む |
| C | デッドコード撤去 | 含む |
| D | 非機能改善（Solid Queue 化・バルク化など） | **別 Issue** |

## 4. 機密情報の取り扱い（横断制約）

実測で得た値と VCR カセットには、アクセストークン・リフレッシュトークン・メールアドレス・
`account_id`・613 件のプレイリスト名が含まれる。これらを GitHub に載せないため、以下を守る。

1. VCR のカセット置き場（`test/vcr_cassettes/`）を `.gitignore` に追加し、**カセットは一切コミットしない**。
   ローカルでの形状確認専用とする。
2. コミットするのは、カセットから形状だけを写した**合成値の JSON fixture**（`test/fixtures/files/spotify_api/`）。
   トークンは `<REDACTED>`、メールアドレスは `test@example.com`、ユーザー ID は `test-user` とし、
   プレイリスト名には seeds に既に含まれる公開データ（原曲名）を使う。
3. gitignore との二重防御として、VCR 側にも `filter_sensitive_data` を設定する。
4. 設計・実装・PR の各ドキュメントに実測値そのものを書かない（形状と有無のみ記述する）。
5. 検証スクリプトはリポジトリ外（作業用ディレクトリ）に置く。

## 5. Phase E — 安全網

### 5.1 方針

**移行前の RSpotify 経路に対するテストは書かない。**

当初「同一のテストファイルが移行前後で 1 字も変えずに pass する」という設計にしていたが、
これは成立しない。本移行は **HTTP リクエストパターンを意図的に変える**からである。

- `index`: 625 req → 13 req（プレイリストごとの `GET /playlists/{id}` を廃止）
- `sync_single`: remove + add → `replace_items`
- `playlist_update_service`: 作成直後の再取得を廃止、ループ削除 → `replace_items` 1 回

「`index` は 613 回の `GET /playlists/{id}` を発行する」と固定したテストは移行時に必ず削除される。
RSpotify の request パターンに合わせた webmock スタブ（rest-client 経由の暗黙 `complete!`、
`?ids=` バッチ、実際に叩いている `/users/{id}/playlists`）を書く労力はそのまま捨てることになる。
rspotify gem 自体も Issue #563 で削除予定である。

耐久性のある資産は**アウトカムのアサーション**（`SpotifyPlaylist` の行、Redis の値、
redirect / JSON）だけであり、それは RSpotify 側のスタブなしで成立する。

したがって方針を 2 本立てにする。

| 目的 | 手段 |
|---|---|
| 移行後の振る舞いを継続的に守る | **テストは `SpotifyApi` 経路に対して 1 度だけ書く** |
| 「移行で振る舞いが変わっていない」ことの確認 | **dev 実環境での前後スナップショット差分** |

### 5.2 前後スナップショット差分

実ログイン済みセッションと実 DB があるため、移行前に現行コードで以下をダンプし、移行後に
同じものを取って diff する。webmock スタブより安く、rest-client の挙動を推測せずに済むため忠実。

- `SpotifyPlaylist` の全行（`spotify_id` / `name` / `original_song_code` / `total` / `followers` / `position`）
- `index` の描画結果
- Redis の進捗キーの値

ダンプは作業用ディレクトリに置き、リポジトリに含めない（プレイリスト名を含むため）。

### 5.3 依存の追加

`Gemfile` の `group :development, :test` に以下を追加する。

- `webmock` — 導入理由は**未スタブの HTTP 呼び出しで即座に落ちること**（`disable_net_connect!`）。
  テストが誤って実 API を叩いてクォータを消費したり、実プレイリストを変更する事故を
  構造的に防げる。既存の `Faraday::Adapter::Test::Stubs` にはこの安全装置がない。
- `vcr` — `SpotifyApi` 経路の fixture 形状を実 API から起こすために使う。異常系
  （429 / 401 / 5xx）は意図的に発生させられないため webmock の手書きスタブで書く。

`test/test_helper.rb` に以下を設定する。

- `WebMock.disable_net_connect!(allow_localhost: true)`
- VCR: `cassette_library_dir` は gitignore 済みディレクトリ、`filter_sensitive_data`、CI 既定は `record: :none`

### 5.4 並列実行の衝突

`test/test_helper.rb` は `parallelize(workers: :number_of_processors)` を有効にしている。
Redis を触るテストはワーカー間でキーが衝突するため、**Redis を使うテストクラスでは
`parallelize(workers: 1)` を宣言する**。

### 5.5 対象

いずれも `SpotifyApi` 経路に対して書く（Phase A / B と同じ PR 内で、実装とともに追加する）。

| テストファイル | 対象 |
|---|---|
| `test/controllers/spotify/playlists_controller_test.rb` | 7 アクション（`index` / `clear_cache` / `sync_single` / `create` / `progress` / `refresh_counts` / `original_songs`）× 正常系・未ログイン・429・401 |
| `test/services/spotify/playlist_update_service_test.rb` | プレイリスト作成 → 差し替えフロー、レート制限時の挙動 |
| `test/controllers/sessions_controller_test.rb` | コールバックでの User 作成と Redis 保存 |
| `test/models/user_test.rb` | `find_or_create_from_auth_hash`（画像なし・email なし・既存ユーザー更新） |
| 原曲名フィルタ | 原曲名に一致しないプレイリストが読み取り・書き込みの両方から除外されることを固定する（後述 7.6） |

## 6. Phase A — OAuth 自前化

### 6.1 OmniAuth ストラテジの新設

`lib/omniauth/strategies/spotify.rb` を新設し、`OmniAuth::Strategies::OAuth2` を継承する。

- `client_options`: site `https://accounts.spotify.com`、authorize_url `/authorize`、token_url `/api/token`
- `uid` は `raw_info['id']`
- `raw_info` は `access_token.get('v1/me').parsed`
- `info` は**現行 `app/models/user.rb` が読む構造と互換にする**。`user.rb` は
  `auth_hash[:info][:images][0][:url]` を読むため、**`images` を配列のまま渡す**こと。
  `GET /me` が返すキーは `account_id` / `display_name` / `email` / `external_urls` /
  `followers` / `href` / `id` / `images` / `type` / `uri`。

`Gemfile` に `omniauth-oauth2` を明示追加する（現在は rspotify 経由の推移依存であり、
将来 rspotify を外した時に無言で壊れる）。

`config/initializers/omniauth.rb`:

- `require 'rspotify/oauth'` を自前ストラテジの require に置換
- scope を `user-read-email playlist-modify-public` に変更
  - `user-library-read` / `user-library-modify` は保存済みライブラリ（`GET /me/albums` 等）の
    権限で、コード上で一度も使われていないため最小権限の原則で外す
  - `user-read-email` は残す（実測で `email` が返っており `users.email` に使用中）
  - `playlist-read-private` は追加しない（対象プレイリストは全件 public）

scope 変更にはユーザーの再認可（1 回の再ログイン）が必要。

### 6.2 `app/models/user.rb`

- `auth_hash.dig(:info, :images, 0, :url).to_s` の安全なアクセスに変更（画像 0 件で `NoMethodError`）
- `email` は `.presence` でフォールバック（`users.email` は `null: false` default `''`）
- `nickname`（`display_name`）も nil ガード
- **既存ユーザーの属性が永久に更新されないバグを修正する**。現在は `find_or_create_by!` の
  ブロック内で属性を設定しているため、ブロックは新規作成時のみ実行され、既存ユーザーの
  nickname / email / image_url は更新されない。

`account_id`（安定識別子）への `uid` 移行は本 PR では行わない。Spotify のユーザー ID は
ユーザーが変更できない固定値で実害が出ておらず、使い道のないカラムを先行して増やさない。

### 6.3 `app/controllers/sessions_controller.rb`

現在の Redis キーは `user.id` の生値で、prefix も TTL もなく、進捗キー（`playlist_update:*` /
`refresh_counts:*`）と同一名前空間に混在している。

- キーを `spotify:auth:<user_id>` に変更する
- `SpotifyApi::UserSession.find` も同じキー体系に合わせる（現在は `redis.get(user_id)` 前提）
- TTL を設定する
- `redis.get` が nil の場合のガード（現状 `JSON.parse(nil)` で `TypeError`）

scope 変更で再ログインが 1 回必要になるため、キー体系の変更を同時に済ませる。

TTL の具体値: 90 日。Spotify の refresh_token は revoke されるまで失効しないため、TTL を
付けると TTL 経過後に再ログインが必要になる。無期限に平文の refresh_token を保持する
リスクと、再ログインの手間のトレードオフとして 90 日を採る。TTL 切れ時はログイン画面へ誘導する。

## 7. Phase B — プレイリスト系の差し替え

### 7.1 セッション取得の集約

`before_action :require_spotify_session` を導入する。現在、以下が 6 箇所にコピペされている。

```
redirect_to root_url unless session[:user_id]   # ← return が無い
auth_hash = JSON.parse(RedisPool.get(...).get(session[:user_id]))
spotify_user = RSpotify::User.new(auth_hash)
```

`return` が無いため、未ログイン時にリダイレクト後も処理が続行し `JSON.parse(nil)` の
`TypeError` になる（`playlists_controller.rb:10, 49, 62, 124, 192`。`original_songs` のみ `return` 付き）。
`before_action` に集約することでこの穴が構造的に消える。

セッションが引けない場合はログイン画面へリダイレクトする。`SpotifyApi::UserSession.find` は
該当ユーザーのトークンが無ければ `nil` を返す（`RSpotify::User#oauth_header` の「最初の
ユーザーのトークンを使う」フォールバックは意図的に持たない）。

### 7.2 置換内容

| 対象 | 変更 |
|---|---|
| `index` / `fetch_playlists_from_spotify` | `SpotifyApi::Playlist.all_mine(session, limit: 50)` の 13 リクエストのみ。`tracks.total` を使い、**follower 数は `SpotifyPlaylist.followers` の既存 DB 値を表示**する |
| `refresh_counts` | `SpotifyApi::Playlist.find` の明示ループで `followers.total` を取得し、`SpotifyRetry.with_retry` で包む。612 リクエストは押した時だけ発生する |
| `sync_single` | 全消し → 全追加を、`replace_items`（先頭 100 件。0 件なら空配列で全消しになる）→ `add_items`（101 件目以降を 100 件ずつ順に追加）に置換。`replace_items` が必ず先に来ること。`RSpotify::Track.find` は廃止し `spotify:track:{id}` を文字列組み立て |
| `create` | `SpotifyApi::UserSession` を `PlaylistUpdateService` に渡す |
| `original_songs` | `SpotifyApi::Playlist.all_mine` に置換 |
| `playlist_update_service` | `SpotifyApi::Playlist.create(session, name:)`（作成直後の再取得を廃止）、`clear_playlist_tracks` のループ → `replace_items(uris: [])` 1 回、`add_items` のバッチを 50 → 100 |
| `SpotifyApi::Response` | `dig` を追加 |
| `config/routes.rb:44` | `match ... via: %i[get post]` → `post` のみ（呼び出し元 `app/views/root/index.html.erb` は `turbo_method: :post` なので安全） |
| `app/views/spotify/playlists/index.html.erb:15` | `link_to ... method: :delete` → `data: { turbo_method: :delete }`（Turbo 下で現在機能していない「最新情報を取得」ボタンの修正） |

### 7.3 follower 数の設計

`GET /me/playlists` は `followers` を返さないため、follower 数には 1 件ごとの
`GET /playlists/{id}` が必要になる。現在は `RSpotify::Base#method_missing` がこれを暗黙に
発火させており、`index` を開くたびに 612 リクエストを消費していた（`index` 全体 625 リクエストの 98%）。

一方でアプリには**明示的な更新ボタン**（`POST /spotify/playlists/refresh_counts`、進捗を
turbo_stream で表示）が既に存在する。したがって責務を分ける。

| 操作 | リクエスト数 | タイミング |
|---|---|---|
| `index`（DB キャッシュあり） | 0 | 変更なし（現状も API を叩かない） |
| `index`（DB キャッシュが空 / `clear_cache` 直後） | **625 → 13** | キャッシュを捨てた後の初回表示 |
| `refresh_counts`（更新ボタン） | 612 | ユーザーが明示的に押した時だけ |

画面の表示項目は何も失われない（キャッシュを捨てた直後のみ follower が 0 表示になり、
更新ボタンを押すと埋まる）。

この設計は `save_playlists_to_db` の修正を前提とする（後述）。

### 7.4 リトライの統合

独自の指数バックオフが 5 箇所に重複している。

- `playlists_controller.rb:231-237`（`refresh_counts`、Retry-After 未参照）
- `playlists_controller.rb:323-329`（`original_songs`、Retry-After 未参照）
- `playlists_controller.rb:500-523`（`fetch_playlists_from_spotify`、Retry-After 参照あり）
- `playlist_update_service.rb:170-191`
- `playlist_update_service.rb:225-248`

すべて `app/models/spotify_retry.rb` の `SpotifyRetry.with_retry` に集約する。Retry-After 準拠・
ジッター付き指数バックオフ・`SpotifyRateLimit` バナー連携が同時に得られる。
リトライが一切ない `sync_single` と `find_user_playlist`（`:396-411`）にも適用する。

**バグ修正**: `handle_ssl_error`（`:211-223`）と `handle_rate_limit_error`（`:225-248`）は
`# retry via caller` とコメントされているが、呼び出し元 `process_originals` に retry 機構が
無いため実際には再試行されず、`raise error` が `call` の `rescue StandardError` まで伝播して
サービス全体が停止する。両メソッドを削除し `SpotifyRetry.with_retry` に統合する。

書き込み系（POST / PUT / DELETE）は `ExternalApi::Connection` の `spotify` プロファイルが
`methods: %i[get]` のみをリトライ対象にしているため Faraday 層では再試行されない
（非冪等性を考慮した意図的な設計）。必要な再試行は `SpotifyRetry.with_retry` で明示的に包む。

### 7.5 `save_playlists_to_db` の修正

現在 `find_or_create_by` のブロック内で属性を設定しているため、**既存レコードが更新されない**。
follower 数を DB 値から表示する設計にすると、`tracks.total` の変化も画面に反映されなくなるため、
本 PR で修正する。

### 7.6 原曲名のプレイリストのみを対象にする

**このアプリが読み書きするのは、名前が原曲名（`OriginalSong.title`）に一致するプレイリストだけ。**

現行コードも `find_original_song_code(playlist_name)` で概ねこの通りに動いているが、暗黙の
前提になっている。`replace_items` / `clear_playlist_tracks` は破壊的操作であり、移行で
呼び出し方が変わるため、**明示的な安全保証として実装に落とす**。

実測では対象ユーザーの 613 件のうち **1 件が原曲名に一致しない**（`幽霊楽団セレクション`）。
このプレイリストは以下のすべてから除外されなければならない。

| 経路 | 保証すべきこと |
|---|---|
| `index` / `save_playlists_to_db` | 一致しないものは `SpotifyPlaylist` に保存しない・表示しない |
| `refresh_counts` | 一致しないものは `GET /playlists/{id}` の対象にしない |
| `original_songs` | 出力 JSON に含めない |
| `sync_single` | **一致しない `id` を渡されたら書き込みを行わず中断する**（`replace_items` / `add_items` を呼ばない） |
| `playlist_update_service` | 原曲名から引いたプレイリストにしか書き込まない |

`sync_single` は `POST /spotify/playlists/:id/sync` で外から `id` を受け取るため、
**サーバ側で原曲名一致を再検証する**。ここが唯一、任意の `id` に対して破壊的操作が
到達しうる経路である。

判定は 1 箇所（`find_original_song_code` 相当）に集約し、読み取り経路と書き込み経路で
同じ判定を使う。

## 8. Phase C — デッドコード撤去

| 対象 | 根拠 |
|---|---|
| `app/services/spotify_web_api/client.rb` + `test/services/spotify_web_api_client_test.rb` | 自身のテスト以外から参照されていない。`/items` パス設計・URI 組み立て・100 件上限ガードは `SpotifyApi::Playlist` に既に存在する |
| `gem 'spotify-client'`（Gemfile） | 上記ラッパー専用の依存 |
| `playlists_controller.rb:7` の `CACHE_TTL` | 未使用 |
| `spotify_playlist.rb:15` の `scope :stale` | 未使用 |
| `app/views/spotify/playlists/create.html.erb` | `create` アクションは progress へリダイレクトするため到達不能 |

**`rspotify` gem 自体は残す。** `app/models/spotify_client/{album,track,audio_features}/rspotify_backend.rb`
が Issue #563 まで生きており、`spotify_retry.rb` / `spotify_rate_limit.rb` も `RestClient::*` 定数を
参照している。Issue の完了条件「`app/controllers` と `app/services` から `RSpotify` の参照が
消えている」は本 PR で満たす。

## 9. 別 Issue に切り出す（D）

以下は #562 のチェックボックスに含まれるが、独立した非機能改善であり別 Issue とする。

- `Thread.new`（`playlists_controller.rb:153, 214`）→ Solid Queue のジョブへ移行
  （`solid_queue ~> 1.5` が Gemfile にあるのに未使用。プロセス再起動で処理が消える）
- Redis 進捗キー（`playlist_update:*` / `refresh_counts:*`）の TTL
- `refresh_counts` の DB 更新を `upsert_all` でバルク化し `sleep 0.2` を撤去
- `refresh_counts` の 96 行インライン実装のサービス化
- `load_progress_info` / `load_refresh_counts_info` が `redis.get` を 2 回呼んでいる（`:417`, `:558`）

## 10. 完了条件

- [ ] `app/controllers/` と `app/services/` から `RSpotify` の参照が消えている
- [ ] 移行前後の dev スナップショット差分に、意図しない `SpotifyPlaylist` の変化がない
- [ ] 原曲名に一致しないプレイリストが、読み取り・書き込みのどの経路からも触られない
      （`sync_single` に一致しない `id` を渡しても書き込みが起きない）
- [ ] `/spotify/playlists` の全機能が実 API で動作する
- [ ] トークン期限切れ後もリフレッシュされ、Redis に書き戻される
- [ ] `clear_cache` 直後の `index` のリクエスト数が 625 → 13 に減っている
- [ ] VCR カセットが git に含まれていない。コミットされた fixture に実在のトークン・
      メールアドレス・`account_id` が含まれていない
- [ ] `make rubocop` / `make minitest` が通る

## 11. 作業前のバックアップ

実施済み。

- DB: `tmp/data/dev-20260726-234331-before-oauth-playlist-migration.bak`
- Redis: 作業用ディレクトリに全キーを JSON でダンプ（トークンを含むためリポジトリ外に保管）
