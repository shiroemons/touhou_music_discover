# YouTube Music 配信日取得機能 設計書

- 作成日: 2026-07-26
- 対象: `ytmusic_albums` / `ytmusic_tracks`
- ブランチ: `feature/ytmusic-distribution-dates`

## 背景

東方同人音楽流通のアルバムが「いつ配信開始されたか」を DB で扱えていない。
`ytmusic_albums` は `release_year`（文字列の年のみ）しか持たず、日単位の配信日が分からない。

### 調査で判明したこと

配信日の取得元候補を実データ（開発DB の 53 アルバム）で検証した結果:

| 候補 | 内容 | 判定 |
| --- | --- | --- |
| YouTube プレイリストページの HTML | `www.youtube.com/playlist?list=<playlist_id>` の `Last updated on <日付>` | **不採用**。プレイリストの「最終更新日」であり、後からトラックや MV が追加されると配信日より後ろにズレる。53 件中 3 件（5.7%）で実際の配信日と乖離した |
| innertube player API の `microformat.publishDate` | 各トラック動画の公開日（UTC） | **採用**。配信代行が自動生成する Art Track は配信開始日に一斉公開されるため、最頻値が配信日と一致する |
| 説明文の `Released on: YYYY-MM-DD` | 原盤（CD）のリリース日。例大祭など頒布イベントの日付 | 配信日とは別概念だが有用なため**併せて保存する** |
| アルバム browse payload | `year` のみ | 日付は取得できない |

検証で乖離した 3 件はいずれも「大多数のトラックが同一日に公開され、少数の既存 MV や先行シングルが後から
プレイリストへ追加された」ケースだった。最頻値を採ることでこれらを正しく判定できる。

| アルバム | HTML の Last updated | Art Track の publishDate 最頻値 |
| --- | --- | --- |
| LIMITED SINGLES season5 | 2026-07-04 | 2026-06-29（16 曲中 10 曲） |
| 彷徨いの冥〜天〜＆境界線上のランデブー | 2026-07-10 | 2026-06-29（8 曲中 7 曲） |
| The Memory of Touhou vol.2 | 2026-07-17 | 2026-06-29（9 曲中 7 曲） |

YouTube 側の日付は UTC 基準のため、**日本の配信日 = `publishDate` + 1 日**とする。

## ゴール

1. アルバム単位の配信日（JST）を DB に永続化し、検索・エクスポート・管理画面から参照できるようにする
2. 判定に使った一次データをすべて残し、集計ルールを変更しても再取得なしで再集計できるようにする
3. rake / 管理画面 / 取り込みバッチの 3 経路から実行できるようにする

## 非ゴール

- Spotify / Apple Music / LINE MUSIC の配信日取得（本設計は YouTube Music のみ）
- 配信日を使った検索 UI やエクスポート形式の変更（別タスク）

## データモデル

### `ytmusic_tracks` への追加（トラック単位の一次データ）

| カラム | 型 | NULL | 内容 |
| --- | --- | --- | --- |
| `published_on` | date | 可 | `microformat.publishDate`（UTC の生値） |
| `uploaded_on` | date | 可 | `microformat.uploadDate`（UTC の生値） |
| `original_released_on` | date | 可 | 説明文の `Released on: YYYY-MM-DD` |
| `provided_by` | string | 可 | 説明文の `Provided to YouTube by <X>` の `<X>`（例: `Rightsscale`）。nil なら自主アップ動画 |
| `art_track` | boolean | 不可（default: false） | `provided_by` が取得できたら true |
| `video_metadata` | jsonb | 可 | 判定に使える生値一式（`channel_id` / `channel_name` / `view_count` / `length_seconds` / `category` / 説明文の先頭数行など） |
| `video_fetched_at` | datetime | 可 | 動画メタデータの取得日時 |

インデックス:

- `(ytmusic_album_id, published_on)` — アルバム単位の集計用
- `video_fetched_at` — 未取得トラックの抽出用

### `ytmusic_albums` への追加（集計結果）

| カラム | 型 | NULL | 内容 |
| --- | --- | --- | --- |
| `distributed_on` | date | 可 | **配信日（JST）** = `youtube_published_on + 1 日` |
| `youtube_published_on` | date | 可 | Art Track の `published_on` 最頻値（UTC の生値） |
| `original_released_on` | date | 可 | Art Track の `original_released_on` 最頻値（原盤リリース日） |
| `distribution_source` | string | 可 | 判定根拠。`art_track_mode` / `all_track_mode` / `single_track` / `failed` |
| `distribution_stats` | jsonb | 可 | 監査用。日付ごとの件数分布、Art Track 数／総数、除外した video_id など |
| `distribution_fetched_at` | datetime | 可 | 集計実行日時 |
| `distribution_track_metadata` | jsonb | 可 | 動画1本ごとの取得結果の配列（`video_id` / `track_number` / `published_on` / `uploaded_on` / `original_released_on` / `provided_by` / `art_track` / `fetched_at`）。取得に失敗した動画も `published_on` 等を `null` にした要素として記録する。`ytmusic_tracks` の行の有無に依存せず配信日を集計・再取得できるようにするための一次データ |

インデックス:

- `distributed_on`
- `distribution_fetched_at`

`distribution_stats` の構造:

```json
{
  "total_tracks": 16,
  "art_tracks": 10,
  "fetched_tracks": 16,
  "published_on_counts": { "2026-06-29": 10, "2021-10-16": 1, "2022-05-01": 1 },
  "art_track_published_on_counts": { "2026-06-29": 10 },
  "original_released_on_counts": { "2026-05-04": 10 },
  "excluded_video_ids": ["xxxxxxxxxxx"],
  "tie_break": false,
  "source_of_truth": "payload"
}
```

`source_of_truth` は集計に使ったデータの出所を示す。`payload`（`distribution_track_metadata` から集計）
と `track_rows`（`ytmusic_tracks` の行から集計。`distribution_track_metadata` 未保存時の後方互換パス）
のいずれかが入る。

## 集計元の決定（track 行の有無に依存しない）

`ytmusic_tracks` の行は `ytmusic:album_tracks_save` が Spotify / Apple Music のトラックと突合して
作るため、**アルバム取り込みより遅れて作られる**。そのため「配信日をまだ知らない、直近追加された
アルバムほど track 行が無い/一部しか無い」という逆転が起きる（実データ検証: 3,742 アルバム中 23 件は
track 行が 0 件、8 件は一部のみで、23 件中 22 件が直近追加されたアルバムだった）。

これを避けるため、集計対象の動画（video_id）は常に `ytmusic_albums.payload['tracks']` を正とする。
取得した動画メタデータは `ytmusic_albums.distribution_track_metadata` に必ず保存し（`ytmusic_tracks`
の行が無くても保存できる）、`YtmusicAlbum#recalculate_distribution!` は `distribution_track_metadata`
が存在すればそれを集計元にする。`payload['tracks']` 自体が縮退していて対象動画が取れない場合だけ、
従来どおり `ytmusic_tracks` の行にフォールバックする。

## 集計ロジック

`YtmusicAlbum#recalculate_distribution!`（HTTP を伴わず DB 上のデータのみで完結。集計元が
`distribution_track_metadata` か `ytmusic_tracks` の行かに関わらず、以下のロジック自体は同一）

1. 対象アルバムのトラック相当データのうち `art_track = true` かつ `published_on` が存在するものを集める
2. `published_on` の**最頻値**を採る
3. 同数タイの場合は**より古い日付**を採用する（初回配信を優先。再アップロードや後追い追加より初出を信頼する）
4. Art Track が 0 件の場合は全トラックの `published_on` 最頻値にフォールバックし、`distribution_source = 'all_track_mode'` を記録する
5. 対象トラックが 1 件のみの場合は `distribution_source = 'single_track'`（統計的な裏付けが弱いことを明示）
6. `published_on` が 1 件も無い場合は各カラムを nil のままにし、`distribution_source = 'failed'` を記録する
7. `distributed_on = youtube_published_on + 1 日`
8. `original_released_on` も同じ最頻値ルールで算出する
9. 分布は必ず `distribution_stats` に記録する

## コンポーネント

### `lib/yt_music/video.rb`（既存を拡張）

以下を追加で公開する。既存の `publish_date` / `upload_date` / `release_date` はそのまま維持する。

- `provided_by` — 説明文冒頭の `Provided to YouTube by <X>` から抽出
- `art_track?` — `provided_by` が present か
- `metadata` — `video_metadata` カラムへ保存する判定用サブセットを返す

### `lib/distribution_date/ytmusic_collector.rb`（新規）

`Repair::YtmusicAlbumPayloads` と同じ設計パターンを踏襲する。

- キーワード引数: `apply: false`（既定 dry-run） / `limit:` / `only_missing: true` / `workers: :ytmusic` /
  `max_attempts:` / `base_interval:` / `out: $stdout`
- 公開 API は `run` / `collect_album` のみ。戻り値は集計結果のハッシュ（`run`）または `CollectOutcome`
  （`collect_album`）
- 対象抽出 → `ids.each_slice(SLICE_SIZE)` → `ParallelRunner.each(slice, workers:, finish:)` で並列処理
- 1 アルバムの処理内で「対象動画の決定 → 動画メタデータ取得 → `distribution_track_metadata` へ保存
  （+ 一致する `ytmusic_tracks` 行があれば従来どおりそちらも更新） → アルバム再集計」を完結させる
- 対象動画は `payload['tracks']` の `video_id` を正とし、`ytmusic_tracks` の行の有無には依存しない。
  `payload['tracks']` が縮退していて動画が1件も取れない場合だけ `ytmusic_tracks` の行にフォールバックする
- `only_missing: true` のときは `distribution_track_metadata` にその `video_id` の `fetched_at` が
  未記録の動画だけを取得対象にする（差分取得。`ytmusic_tracks` の行が無いアルバムでも効く）
- 取得結果は成功・失敗を問わず必ず `distribution_track_metadata` へ保存する
- 進捗・サマリは `out.puts` に出力（`Rails.logger` はエラー専用）

### `app/models/ytmusic_album.rb` / `app/models/ytmusic_album/distribution_track_metadata_record.rb`（既存を拡張・新規）

- `recalculate_distribution!` — `distribution_track_metadata` が存在すればそれを、無ければ
  `ytmusic_tracks` の行を集計元として使う（`DistributionTrackMetadataRecord` が両者を
  `DistributionCalculator` が期待する同一インターフェースへ変換する）
- スコープ `distribution_missing` — `distributed_on` が nil または `distribution_source = 'failed'` の行

### `app/models/ytmusic_track.rb`（既存を拡張）

- `update_video_metadata(video)` — `YtMusic::Video` の値を各カラムへ保存する
- スコープ `video_metadata_missing` — `video_fetched_at` が nil の行

## 実行手段

| 手段 | 内容 |
| --- | --- |
| `rake ytmusic:fetch_distribution_dates` | `APPLY=1` / `LIMIT` / `ONLY_MISSING=1`（既定 1） / `ALL=1` / `MAX_ATTEMPTS` / `PARALLEL_WORKERS` |
| `rake ytmusic:recalculate_distribution_dates` | 保存済みトラックから再集計のみ（HTTP なし・高速） |
| `Admin::Actions::FetchYtmusicDistributionDates` | 管理画面から全件実行。`Admin::ActionProgress` で進捗表示 |
| `Admin::Actions::FetchYtmusicAlbumDistributionDate` | member アクション（1 アルバム単位の再取得） |
| `ytmusic:album_tracks_save` への統合 | トラック保存後、`video_fetched_at` が nil のトラックだけ自動取得して集計する |

バックフィルは既存 3,742 アルバム（約 37,000 動画）を対象とするため、`LIMIT` と `ONLY_MISSING=1` で
分割実行する。`ONLY_MISSING` により中断・再開が安全に行える。

## エラー処理

`Repair::YtmusicAlbumPayloads` の規約に準拠する。

- 1 動画の取得失敗は `rescue StandardError` で握り、該当動画のみ `published_on` 等を `null` にした
  `distribution_track_metadata` の要素として記録し（`fetched_at` は設定する）残りで集計を続行する
- 取得は指数バックオフ + ジッタ（±30%）で `max_attempts` 回までリトライする
- アルバム内の全動画が失敗した場合は `distribution_source = 'failed'` を記録し、
  `ONLY_MISSING` の再試行対象として残す
- 例外は `Rails.logger.error` に `album_id` / `video_id` / 例外クラス付きで記録する

## テスト

minitest。外部 HTTP は Fake オブジェクトで置き換える（本リポジトリは webmock / vcr を使わない）。

- `test/lib/yt_music/video_test.rb` — `provided_by` / `art_track?` / `metadata` のパース
- `test/models/ytmusic_album_test.rb` — 集計ロジック（最頻値・タイブレーク・フォールバック・
  `single_track`・`failed`・`distribution_stats` の内容）に加え、`distribution_track_metadata` が
  あればそれを（`source_of_truth: payload`）、無ければ `ytmusic_tracks` の行を
  （`source_of_truth: track_rows`）集計元にすること
- `test/models/ytmusic_track_test.rb` — `update_video_metadata` の保存内容
- `test/lib/distribution_date/ytmusic_collector_test.rb` — dry-run / apply / `only_missing` の差分取得 /
  取得失敗時に他アルバムの処理が止まらないこと に加え、`ytmusic_tracks` の行が1件も無い/一部しか無い
  アルバムでも `payload['tracks']` の `video_id` から集計できること（回帰テスト）、取得結果
  （成功・失敗とも）が `distribution_track_metadata` へ保存されること、`only_missing` が
  `distribution_track_metadata` の `fetched_at` を見て差分取得すること、`payload['tracks']` が
  無いアルバムは `ytmusic_tracks` の行にフォールバックすること

## 影響と移行

- 既存カラムの変更・削除はなく、すべて追加のみ。既存機能への影響はない
- バックフィル前は `distributed_on` が nil のため、参照側は nil を許容すること
- 検証済みの 53 件のうち 3 件は、HTML 方式で得ていた 7/05・7/11・7/18 が本方式では 6/30 に補正される
