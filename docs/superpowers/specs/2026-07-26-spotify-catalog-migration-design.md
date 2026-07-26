# Spotify カタログ取得系の SpotifyApi 移行 設計書

対象 Issue: #561 [Spotify移行 2/4] / 親 Issue: #564 / 前提: #560 (PR #567)

## 背景

PR #567 で `lib/spotify_api/` を新設したが、`app/` からは一切呼ばれていない。
本設計はカタログ取得系（アルバム・トラック・オーディオ特性）を `RSpotify::*` から
`SpotifyApi::*` へ切り替えるための設計を定める。

## 最重要の前提: 検索結果は簡易オブジェクト

Spotify の `GET /search` が返す album は **SimplifiedAlbumObject** であり、
以下を **含まない**。

| 欠落するフィールド | 参照している既存コード |
|---|---|
| `label` | `SpotifyAlbum.save_album`（`app/models/spotify_album.rb:25`） |
| `external_ids`（UPC） | `SpotifyAlbum.save_album`（`:27`）、`search_and_save_album_by_jan`（`:197`） |

`GET /albums/{id}/tracks` が返す track も **SimplifiedTrackObject** であり、
`external_ids`（ISRC）を含まない（`SpotifyTrack.save_track`、`app/models/spotify_track.rb:25` が参照）。

rspotify は `RSpotify::Base#method_missing` が nil 属性へのアクセスで暗黙に
`complete!`（追加 HTTP リクエスト）を発火させ、この欠落を裏で埋めていた。
これが Development Mode のクォータ枯渇の主因（#558）である。

`SpotifyApi::Response` は**未定義キーで nil を返すだけ**（`lib/spotify_api/response.rb:58`）なので、
単純置換すると次の障害が起きる。

- `save_album` の `s_album.label != TOUHOU_MUSIC_LABEL` が常に真 → **全アルバムが無言で保存されなくなる**
- `save_track` の `s_track.external_ids['isrc']` が nil → **ISRC なしの Track が量産される**
- `search_and_save_album_by_jan` の UPC 照合が常に失敗 → **JAN 補完機能が全滅**

したがって「DB 先行チェック + 新規のみフル取得」は**クォータ最適化ではなく動作要件**である。

### #559 のリスクは解消しない（2026-07-26 実 API 調査により訂正）

当初この設計書には「`Album.find` は market を送らないので `available_markets` が確実に
payload に入り、#559 の危険が構造的に解消される」と書いていたが、**これは誤りだった**。

実 API を調査した結果:

- 無作為30件のうち **26件（86.7%）が `available_markets` を空配列で返す**（market 未指定でも）
- 空配列のアルバムを `market=JP` で取得すると `is_playable=true` / `restrictions=nil` であり、
  **配信終了ではない**
- [Get Album のリファレンス](https://developer.spotify.com/documentation/web-api/reference/get-an-album)に
  「If neither market or user country are provided, the content is considered unavailable
  for the client」と明記されている。Client Credentials（ユーザーの国情報なし）＋ market 未指定
  という本アプリの呼び方が、まさにこの条件に当たる
- [2026年2月の changelog](https://developer.spotify.com/documentation/web-api/references/changes/february-2026)で
  `available_markets` は Album から `[REMOVED]`、リファレンス上も Deprecated

ただし **market を送らない判断自体は本 PR では正しい**。market を送ると `available_markets` が
完全に消えるため `jp_available?` が全件 false になり、さらに悪化する。

本質的な解決は #559 で `jp_available?` を `is_playable` ベースへ移行することであり、
本 PR では下記の暫定ガードのみを入れる。

### payload 上書きガード（#559 の部分対応）

`payload` を保存する際、**新しい値の `available_markets` が空で、既存が非空なら既存を保持する**。
`SpotifyAlbum#payload_preserving_available_markets` として実装し、
`save_album` と両バックエンドの `update_albums` から使う。

これを入れないと `spotify:update_spotify_albums` を1回流すだけで約87%のアルバムの
`jp_available?` が true → false に反転し、`active_candidate_score` による重複アルバムの
選定が狂う。新しい値が非空なら、件数が減っていてもそのまま採用する
（実際に配信市場が減った場合は反映されるべきため）。

## 切り替え方式

`SPOTIFY_NATIVE_CLIENT`（`SpotifyApi.native_client_enabled?`）による一括切り替え。

- **既定値を `true`（SpotifyApi 経路）に変更する**（現状は false）。
  問題発生時は `SPOTIFY_NATIVE_CLIENT=0` で旧経路に戻す。
- rspotify 互換シムは**作らない**。新旧それぞれの処理フローを素直に書く。
- 分岐は**バックエンドクラスの選択1箇所**に集約し、#563 では
  `*_backend.rb`（rspotify 側）の削除とディスパッチャの分岐削除だけで撤去できるようにする。

## クラス構成

```
app/models/spotify_client/album.rb                        … ディスパッチャ + 共通オーケストレーション
app/models/spotify_client/album/native_backend.rb         … SpotifyApi 経路
app/models/spotify_client/album/rspotify_backend.rb       … 既存ロジックを移設（#563 で削除）
app/models/spotify_client/track.rb                        … ディスパッチャ
app/models/spotify_client/track/native_backend.rb
app/models/spotify_client/track/rspotify_backend.rb       … #563 で削除
app/models/spotify_client/audio_features.rb               … ディスパッチャ
app/models/spotify_client/audio_features/native_backend.rb
app/models/spotify_client/audio_features/rspotify_backend.rb  … #563 で削除
```

`SpotifyAlbum` / `SpotifyTrack` / `SpotifyTrackAudioFeature` は **変更しない**。
`SpotifyApi::Response` は `label` / `external_ids` / `external_urls` / `as_json` に
そのまま応答するため、フル取得したオブジェクトを渡す限り互換シムは不要。

### 責務分担

`SpotifyClient::Album`（ディスパッチャ）に残すもの — API を叩かない処理:

- 定数 `LIMIT` / `SEARCH_LIMIT` / `JAN_SEARCH_LIMIT` / `KEYWORD` ほか
- `fetch_touhou_albums` … 年ループ・ParallelRunner・SpotifyRetry・進捗通知
- `fetch_missing_albums_by_apple_music_jan` … 集計・進捗・レート制限打ち切り
- `save_tracks(spotify_album, s_tracks)` … `SpotifyTrack.save_track` のループ
- `missing_spotify_albums_with_apple_music` / `with_spotify_retry` / `record_jan_search_progress`
- `backend` … `SpotifyApi.native_client_enabled? ? NativeBackend : RspotifyBackend`

バックエンドに委譲するもの — API の叩き方が異なる処理:

| メソッド | 役割 |
|---|---|
| `search_and_save_albums(keyword, year)` | 検索 + ページング + `process_album` |
| `process_album(s_album)` | アルバム保存 + トラック取得 |
| `search_and_save_album_by_jan(album, logger:)` | UPC 検索して1件保存。`:created` / `:skipped` / `:missing` / `:errors` を返す |
| `update_albums(spotify_albums)` | 既存アルバムのメタデータ更新 |
| `fetch_and_process_album(spotify_id)` | ID 指定で取得して `process_album`（`Admin::Actions::FetchMissingSpotifyTracks` 用） |

`SpotifyClient::Album` の公開メソッド名と引数は現状維持する
（`admin/actions.rb` と既存テストのスタブがそのまま動くようにするため）。

## Native バックエンドの処理フロー

### process_album

```
1. SpotifyAlbum.find_by(spotify_id:) で既存を引く
2. 既存あり            → API を一切叩かない
   既存なし かつ 簡易  → SpotifyApi::Album.find(id) でフル取得 → SpotifyAlbum.save_album
   既存なし かつ フル  → そのまま SpotifyAlbum.save_album（追加リクエスト無し）
3. total_tracks == spotify_tracks.count なら終了
4. トラックをページングで取得（下記）
5. 未保存のトラックだけ SpotifyApi::Track.find でフル取得し save_tracks
```

簡易/フルの判別は `s_album.key?(:label)` で行う（`Response#key?` は文字列・シンボル両対応）。

### トラックのページング

**必ず `GET /albums/{id}/tracks` を使う。`GET /albums/{id}` に埋め込まれた `tracks` を
1 ページ目として再利用してはならない。**

```
page = SpotifyApi::Album.tracks(id, limit: LIMIT, offset: 0)
loop:
  items に page.items を追加
  page.last_page? なら終了            # next が null かで判定（items.size < limit では判定しない）
  page.items が空なら終了              # 異常応答での無限ループ防止
  page = SpotifyApi::Album.tracks(id, limit: LIMIT, offset: items.size)
```

#### 埋め込み tracks を再利用してはならない理由（2026-07-26 実測により判明）

当初は「1 リクエスト節約できる」として埋め込みを再利用する実装にしていたが、
**データ破壊を招くため撤回した**。アルバム `4nv3iLy6coSBFZixtCsoVP` での実測:

| 取得元 | 返る track ID | `linked_from` |
|---|---|---|
| `GET /albums/{id}` の埋め込み `tracks` | `6pu4soizxvmV4ZWwTzcIhh` … | **全件にあり**（relinked ID） |
| `GET /albums/{id}/tracks` | `0XsewX4zS02mbSS1BkNbj0` … | なし（canonical ID） |
| DB の既存 `spotify_tracks.spotify_id` | `0XsewX4zS02mbSS1BkNbj0` … | canonical と一致 |

`market` を指定していないにもかかわらず、**アルバムオブジェクトに埋め込まれた tracks は
track relinking された市場別 ID** で返る（`linked_from.id` が canonical ID を指す）。
専用のトラック一覧エンドポイントは relinking されず canonical ID を返す。

既存データは canonical ID で保存されているため、埋め込みを再利用すると
`SpotifyTrack.exists?` による存在判定をすり抜け、**同じ曲の行が二重に作られる**。

追加リクエストが発生するのは新規・未完アルバムのみ（`process_album` は
完全なアルバムでは早期 return する）ため、実運用でのコストは小さい。

なお、この節は既存の `fetch_tracks` が定義されていながら `process_album` から
呼ばれておらず、**51 曲以上のアルバムで最初の 50 曲しか保存されない**バグの修正も兼ねる。

### トラックの DB 先行チェック

```
simplified_tracks.filter_map do |t|
  next if SpotifyTrack.exists?(spotify_album_id: spotify_album.id, spotify_id: t.id)
  SpotifyApi::Track.find(t.id)
end
```

既存トラックは API を叩かずスキップする。簡易オブジェクトで payload を上書きすると
`external_ids` を失って情報が劣化するため、**更新もしない**。

### search_and_save_album_by_jan

`upc:` 検索の結果も簡易オブジェクトのため、候補を順にフル取得して UPC を照合する。
実運用では候補は 0〜1 件であり、`lazy` により最初に一致した時点で打ち切る。
一致後のロジック（label 判定・別アルバムへの紐付き検出・保存確認）は既存と同一。

## 例外の扱い

フラグが存在する間は新旧どちらの例外も飛びうるため、共通定数で両方を受ける。
#563 では rspotify 側の要素を削除するだけでよい。

`app/models/spotify_retry.rb`:

```ruby
RATE_LIMIT_ERRORS = [
  RestClient::TooManyRequests,        # #563 で削除
  SpotifyApi::RateLimitError
].freeze

TRANSIENT_ERRORS = [
  RestClient::InternalServerError, RestClient::BadGateway,        # #563 で削除
  RestClient::ServiceUnavailable, RestClient::GatewayTimeout,     # #563 で削除
  RestClient::Exceptions::OpenTimeout, RestClient::Exceptions::ReadTimeout,  # #563 で削除
  SpotifyApi::ServerError,
  Faraday::TimeoutError, Faraday::ConnectionFailed, Faraday::SSLError,
  Net::OpenTimeout, Net::ReadTimeout
].freeze
```

`SpotifyApi::QuotaExceededError` は `RateLimitError` のサブクラスだが、
`Retry-After` が数時間規模で待っても回復しないため、**リトライせず即座に再送出する**。
ただし管理画面バナーに反映するため `SpotifyRateLimit.record!` は行う。
`rescue *RATE_LIMIT_ERRORS` より前に専用の rescue 節を置く。

`SpotifyRateLimit.retry_after_seconds`（`:63-69`）は、
`SpotifyApi::ApiError#retry_after` を**最優先**で読む分岐を先頭に追加する。
rest-client 形式（`http_headers`）の分岐は #563 まで残す。

`rescue RestClient::TooManyRequests` を `rescue *SpotifyRetry::RATE_LIMIT_ERRORS` に置換する箇所:

- `app/models/admin/action.rb:64`（Issue に記載が無いが必要）
- `app/models/admin/actions.rb:111` / `:486` / `:655` / `:736`
- `app/models/spotify_client/album.rb:119`（`fetch_missing_albums_by_apple_music_jan`）

タイムアウト系の rescue（`album.rb:64`, `:78`）は各バックエンドに移り、
Native 側は `Faraday::TimeoutError` / `Faraday::ConnectionFailed` / `Net::OpenTimeout` を受ける。

## 削除するもの

- `SpotifyClient::Album.fetch_albums`（`:139-152`）… 呼び出し元なしのデッドコード。
  同時に `SpotifyArtist.save_artist` も呼び出し元が無いか確認して削除する。
- `SpotifyClient::Album.fetch_tracks`（`:154-169`）… rspotify 固有の `tracks_cache` を使うため、
  Native 側のページング実装に置き換える。RspotifyBackend には現状のまま残す。

## 設定変更

`lib/spotify_api/config.rb`:

```ruby
@native_client_enabled = truthy?(ENV.fetch('SPOTIFY_NATIVE_CLIENT', 'true'))
```

`SPOTIFY_NATIVE_CLIENT=0` / `false` / `no` / `off` で旧経路に戻せること。

## 今回やらないこと

以下は #558（クォータ枯渇の解消）で別途対応する。

- `SEARCH_LIMIT` の設定値化（現在 10 のまま）
- `SpotifyRetry` のスコープを「年全体」から「1ページ」へ縮小

以下は #559 で本対応する。

- `jp_available?` を `available_markets` ベースから `is_playable` ベースへ移行し、
  判定結果を DB カラムに永続化する
- `market` を送る呼び出しと送らない呼び出しの用途分離
- 削除系 rake タスク（`prune_unavailable_albums` ほか）の比率アボート等のセーフガード

## 実 API 検証結果（2026-07-26）

クォータが回復していたため、本番資格情報で実施した。

### 前提の裏付け

| 検証項目 | 結果 |
|---|---|
| 検索結果に `label` が無い | `key?(:label)=false` — 前提どおり |
| 検索結果に `external_ids` が無い | `key?(:external_ids)=false` — 前提どおり |
| album tracks が簡易（`external_ids` 無し） | そのとおり。`Track.find` が必要 |
| `search` の `limit=50` | 通る（エンドポイント制限は猶予中） |
| `audio-features` | 生存（tempo 取得成功） |
| `GET /tracks/{canonical_id}` が ID を変えない | 一致（`update_tracks` 経路は安全） |

### 書き込み経路

トランザクション内で実行しロールバックする方式で検証した。

- 14 曲アルバム: `albums/{id}` ×1 + `tracks/{id}` ×14、ISRC 完全一致で復元
- 55 曲アルバム: 1 ページ目 + 2 ページ目 + `tracks/{id}` ×55、ISRC 完全一致で復元

### JAN 補完（`fetch_missing_albums_by_apple_music_jan`）

Spotify 未登録だった 20 件に対して実行した結果:

- created 12 / missing 8 / errors 0
- 追加された 76 トラックはすべて ISRC 付き、全アルバムで `tracks == total_tracks`
- 全件 `jp_available? = true`（markets 184 件）
- 重複・孤児レコード・`linked_from` 付きトラックはいずれも 0 件
- API コスト 120 リクエスト（search 20 + albums 12 + tracks 一覧 12 + tracks 76）

未取得の 8 件はすべて JAN プレフィックス `4580547`（別流通）で、Spotify に未配信だった。

## テスト

- `test/models/spotify_client_album_test.rb`
  - 既存4件は RspotifyBackend 経路として明示的にフラグ off で実行する
  - Native 経路の同等テストを追加する
- **新規（Native）**: 検索結果の簡易オブジェクトから `Album.find` でフル取得して保存すること
- **新規（Native）**: 既存 `SpotifyAlbum` があるとき `Album.find` を呼ばないこと（クォータ回帰テスト）
- **新規（Native）**: 既存 `SpotifyTrack` があるとき `Track.find` を呼ばないこと（クォータ回帰テスト）
- **新規（Native）**: 51 曲以上のアルバムでページングが動作すること
- **新規（Native）**: 埋め込み `tracks` が relinked ID でも、保存される `spotify_id` は
  `Album.tracks` が返す canonical ID になること（重複保存の回帰テスト）
- **新規（Native）**: `next` が非 null かつ `items` が空でも無限ループしないこと
- **新規（Native）**: `Album.find` に `market` を渡さないこと（#559 回帰テスト）
- **新規**: `available_markets` が新レスポンスで空／キー欠損のとき既存値を保持すること。
  非空なら件数が減っていても更新すること。両バックエンドの `update_albums` 経由でも保持されること
- `test/models/spotify_retry_test.rb` … `QuotaExceededError` を即再送出することのテストを追加
- `test/models/spotify_rate_limit_test.rb` … `ApiError#retry_after` を優先して読むことのテストを追加
- `test/models/admin/action_test.rb:193` … 両バックエンドに対応させる
- `test/lib/spotify_api/config_test.rb` … 既定値 true への変更を反映
