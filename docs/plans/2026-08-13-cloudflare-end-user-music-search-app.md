# Cloudflare エンドユーザー向け東方音楽検索アプリ計画

**Goal:** 既存Railsアプリをカタログの基幹システムとして維持しつつ、東方同人音楽流通で配信されている作品を検索・絞り込み・ブックマーク・いいねできる、ログイン任意のエンドユーザー向けWebアプリをCloudflare上に構築する。

**Architecture:** 新アプリは既存Railsとは別リポジトリ、別デプロイで運用する。実行時にRailsへ問い合わせず、Railsが生成する版付きカタログスナップショットをCloudflare D1へ手動投入する。公開カタログとユーザーデータは別々のD1に分離する。

**Tech Stack:** Cloudflare Workers Static Assets / React Router v8 SSR / TypeScript / Cloudflare Vite plugin / D1 / Drizzle ORM / Better Auth / Google OIDC

## 1. 決定事項

- 既存Railsはカタログ収集、名寄せ、補正、原曲対応を担う基幹システムとして残す。
- Cloudflareアプリは検索リクエスト時にRailsへ依存しない、エンドユーザー向けの独立アプリとする。
- 既存の `music.touhou-search.com` は変更せず、新アプリを別ドメインで並行運用する。
- Cloudflare Pagesではなく、Workers Static AssetsとReact RouterのSSR構成を採用する。
- D1は公開カタログ用の `CATALOG_DB` と認証・ユーザー操作用の `USER_DB` に分ける。
- カタログ同期は、当初は管理者が実行する完全スナップショット方式とする。Cron、Queue、公開インポートAPIは作らない。
- Googleログインを提供するが、検索と詳細閲覧はログインなしで利用可能にする。
- ブックマークといいねは別の機能として扱い、アルバムと楽曲の両方を対象にする。
- YouTube由来のアルバム配信日は取り込むが、公開画面では出典名を付けず「配信開始日（推定）」と表示する。
- 日付以外の配信サービス一覧では、YouTube Musicの名称、配信状況、リンクを従来どおり表示する。

## 2. システム構成

```text
Rails / PostgreSQL（基幹・正本）
        |
        | versioned full snapshot（手動）
        v
Cloudflare importer
        |
        +--> CATALOG_DB（公開カタログ・検索投影）
        |
Browser --> Worker（React Router SSR / API / Better Auth）
                    |
                    +--> CATALOG_DB
                    +--> USER_DB（認証・ブックマーク・いいね）
```

Cloudflareアプリの基本構成はCloudflare公式の[React Router向けガイド](https://developers.cloudflare.com/workers/framework-guides/web-apps/react-router/)に合わせる。静的ファイルはWorkers Static Assetsから配信し、SSRとAPIだけをWorkerで処理する。

### 2.1 D1の分離

`CATALOG_DB`には次のデータを保持する。

- カタログ世代とactive世代
- サークル
- アルバム
- 楽曲
- 原作
- 原曲
- 各エンティティ間の中間テーブル
- 配信サービス
- アルバム・楽曲ごとの配信サービスURLと配信状態
- 検索用projection、alias、FTS5仮想テーブル
- 推定配信日と内部監査情報

`USER_DB`には次のデータを保持する。

- Better Authのuser、session、account、verification
- ブックマーク
- いいね

D1間には外部キーを作れないため、ブックマーク・いいね登録時に `CATALOG_DB` で対象の存在と公開可否を検証する。マイページでは `USER_DB` から対象IDを取得し、`CATALOG_DB` でまとめて表示情報を解決する。

## 3. カタログモデル

既存Railsのcanonical IDをそのまま公開カタログの安定IDとして利用する。

| エンティティ | 安定ID | 主な関係 |
|---|---|---|
| サークル | Rails UUID | アルバムと多対多 |
| アルバム | Rails UUID | サークル、楽曲、配信サービスと関連 |
| 楽曲 | Rails UUID | 収録アルバム、原曲、配信サービスと関連 |
| 原作 | 既存code | 原曲を所有 |
| 原曲 | 既存code | 楽曲と多対多 |

楽曲は「アルバム内に収録されたcanonical track」として扱う。同じ録音が複数アルバムへ収録された場合の横断統合はMVPでは行わない。ブックマークといいねは配信サービス固有IDではなく、このcanonical album／track IDへ紐づける。

配信状況はサービスごとに分断した検索結果を作らず、canonical album／trackの中へ関連付ける。

- アルバム: `available / partial / unavailable / unknown`
- 楽曲: `available / unavailable / unknown`
- 初期サービス: Spotify、Apple Music、YouTube Music、LINE MUSIC
- 地域・storefront別の表示はMVP対象外

削除・非公開になったcanonical entityは、ユーザー情報を壊さないよう即時物理削除しない。公開検索から除外し、既存ブックマークでは「公開終了」と表示できる最小情報を残す。

## 4. 配信開始日（推定）

Railsには `ytmusic_albums.distributed_on`、`distribution_source`、`distribution_stats`、`distribution_fetched_at` が既に存在する。現在の算出方法は [`YtmusicAlbum::DistributionCalculator`](../../../app/models/ytmusic_album/distribution_calculator.rb) を正とし、Cloudflare側では再計算しない。

現在の算出値は、Art Trackを優先して動画公開日の最頻値を選び、同数の場合は古い日付を採用し、UTCからJSTへの補正として1日を加えたアルバム単位の日付である。そのため、公式に確定した全サービス共通の発売日としては扱わない。

### 4.1 公開フィールド

公開APIでは次のフィールドだけを返す。

```ts
type EstimatedDistributionDate = string | null; // YYYY-MM-DD

interface AlbumSummary {
  estimatedDistributionDate: EstimatedDistributionDate;
  // 他のアルバム表示項目
}
```

- UIラベルは常に「配信開始日（推定）」とする。
- 日付付近のラベル、説明、ツールチップ、aria-labelには出典サービス名を含めない。
- `youtubePublishedOn`、出典、算出方式、動画ID、生payloadは公開APIへ含めない。
- SEOの `datePublished` には使用せず、canonical albumの通常リリース日を使用する。
- 楽曲固有の日付は作らない。楽曲画面では「収録アルバムの配信開始日（推定）」としてアルバムの日付を表示する。

### 4.2 内部監査情報

非公開の内部情報として次を保持する。

- 取得元
- Rails側の取得レコードID
- 算出方式
- 算出品質
- 算出アルゴリズム版
- 最終取得日時
- 最終正常値の取得日時
- 最新取得の状態

正常な日付が取得できた場合だけ値を更新する。後続の取得が `degraded` または `failed` になった場合は既知の正常値を保持し、取得状態だけを更新する。日付を消すのはRails側から明示的な訂正・取消が出力された場合に限定する。

### 4.3 検索での利用

- アルバムカード、アルバム詳細、アルバム検索結果へ表示する。
- 楽曲カード・詳細では収録アルバムの日付として表示する。
- `distribution_year` ファセットを追加する。
- `distribution_newest` 並び替えを追加する。
- 推定配信日がない項目は新着順の末尾へ置く。
- 同じ日付の項目はcanonical IDをtie-breakにして順序を固定する。
- 通常の「リリース年」と推定日の「配信年」は別ファセットとして提供する。

既存の非公開取得方式をCloudflareへ移植しない。公開前にデータの再利用条件を確認し、現在のデータを公開できない場合は、東方同人音楽流通など運営者が提供する許諾済みフィードへ取得元を置き換える。YouTube由来データを扱う場合は[YouTube API Services Developer Policies](https://developers.google.com/youtube/terms/developer-policies)を公開判定のゲートにする。

## 5. カタログ同期

### 5.1 Rails exporter

既存のTSV／Algolia向けexporterは正式な同期契約としては使わず、専用のversioned exporterを追加する。

出力はテーブル単位のJSONLとmanifestで構成する。

```json
{
  "schema_version": 1,
  "snapshot_id": "2026-08-13T12:00:00Z-<digest>",
  "generated_at": "2026-08-13T12:00:00Z",
  "files": [
    {
      "name": "albums.jsonl",
      "sha256": "<digest>",
      "rows": 3774
    }
  ]
}
```

export対象は次のとおり。

- albums、tracks、circles、originals、original_songs
- circle／album、track／original_songの中間関係
- 各配信サービスのalbum／track availabilityとURL
- 表示名、検索alias、画像URL
- 推定配信日と非公開の監査用属性
- 非公開化・訂正・取消情報

生のサービスAPIレスポンス、Cookie、APIキー、OAuth token、ユーザー情報、画像本体は出力しない。

### 5.2 D1 importer

1. manifestと全ファイルのchecksumを検証する。
2. 未公開の新しい `generation_id` へ分割投入する。
3. ID形式、必須値、参照整合性、重複、row countを検証する。
4. 検索projectionとFTS5 indexを再構築する。
5. 代表的な検索smoke testを実行する。
6. active generationを1操作で切り替える。
7. 現行世代と直前世代を残し、それ以前を後から削除する。

同じ `snapshot_id` の再投入は冪等にする。失敗時はactive generationを変更せず、利用中の公開カタログを維持する。FTS5は復元可能な派生物とし、正規化済みスナップショットを非公開の外部保管先にも保持する。

## 6. 検索

D1が公式に対応する[FTS5](https://developers.cloudflare.com/d1/sql-api/sql-statements/)を検索候補の抽出に使い、通常のjunction tableとindexでfacetを適用する。

### 6.1 検索対象

- サークル名
- アルバム名
- 楽曲名
- 原作名
- 原曲名
- 別名、旧表記、サービス固有表記、英語名、ローマ字

取り込み時にNFKC、ASCIIの大小文字、全半角、ひらがな・カタカナを正規化し、表示用文字列とは別の検索列へ格納する。

- 3文字以上: FTS5 `trigram`
- 1～2文字: indexed alias tableの完全一致・前方一致
- 全面 `%LIKE%` は使用しない
- FTS queryはliteralとしてescapeし、長さを制限する
- sort、facet名はallow-listで検証する

### 6.2 ファセット

- 配信サービス
- サークル
- 原作
- 原曲
- リリース年
- 配信年

同一ファセット内はOR、異なるファセット間はANDとする。検索結果は「すべて／アルバム／楽曲」のタブに分け、サークル・原作・原曲への一致は関連するアルバム／楽曲を返す。

1ページ20件、最大50件とし、relevanceとcanonical IDを使うcursor paginationにする。検索結果、総件数、facet件数は上限付きprepared statementとして発行し、D1の `rows_read` を計測する。

## 7. 認証・ブックマーク・いいね

GoogleログインはBetter Authの安定版とGoogle OIDCを使用する。

- scopeは `openid email profile` のみ
- ユーザーの外部識別子はemailではなくOIDC `sub`
- callbackは `https://<APP_ORIGIN>/api/auth/callback/google`
- secretsはWorker secretsに保存する
- state、PKCE、CSRF／Origin検査を無効化しない
- Cookieは `HttpOnly; Secure; SameSite=Lax`
- sessionとaccountは `USER_DB` に保存する

未ログインでも検索・詳細閲覧・配信サービスへの遷移を許可する。ブックマークまたはいいね操作時だけログインを要求し、認証後は操作元のページへ戻す。APIは未認証mutationへ401を返す。

### 7.1 ブックマーク

- 対象はalbumまたはtrack
- ユーザー本人だけが参照できる
- `UNIQUE(user_id, target_type, target_id)` で重複を防ぐ
- PUT／DELETEを冪等にする
- マイページでアルバム／楽曲別に確認できる

### 7.2 いいね

- 対象はalbumまたはtrack
- 本人の状態と公開件数を返す
- `UNIQUE(user_id, target_type, target_id)` で重複を防ぐ
- PUT／DELETEを冪等にする
- ハートボタンはoptimistic UIとし、失敗時にrollbackする
- `aria-pressed`、キーボード操作、`prefers-reduced-motion` に対応する
- 通常時は短い拡大・バーストアニメーションを付ける

## 8. 公開画面とAPI

### 8.1 画面

- `/` — 検索入口、新着アルバム
- `/search` — 検索結果とfacet
- `/circles/:id` — サークル詳細
- `/albums/:id` — アルバム詳細
- `/tracks/:id` — 楽曲詳細
- `/originals/:code` — 原作詳細
- `/original-songs/:code` — 原曲詳細
- `/mypage` — ブックマーク、いいね

詳細ページはSSR、canonical URL、OG metadataを備える。検索結果ページはクエリの組み合わせによる重複を避けるため `noindex` とする。認証済みレスポンス、個人状態、`Set-Cookie` を含むレスポンスは共有cacheへ保存しない。

### 8.2 API

```text
GET    /api/search
GET    /api/engagement?targets=album:<id>,track:<id>
PUT    /api/bookmarks/:type/:id
DELETE /api/bookmarks/:type/:id
PUT    /api/likes/:type/:id
DELETE /api/likes/:type/:id
*      /api/auth/*
```

`GET /api/search` は次のqueryを受け付ける。

```ts
type SearchType = "all" | "album" | "track";
type SearchSort = "relevance" | "distribution_newest" | "release_newest";

interface SearchQuery {
  q?: string;
  type?: SearchType;
  service?: string[];
  circle?: string[];
  original?: string[];
  originalSong?: string[];
  releaseYear?: number[];
  distributionYear?: number[];
  sort?: SearchSort;
  cursor?: string;
  limit?: number; // default: 20, max: 50
}
```

`GET /api/engagement` は最大50対象まで受け付け、公開いいね数と、ログイン済みの場合だけ本人のいいね・ブックマーク状態を返す。target typeは `album | track` のallow-listとする。

## 9. セキュリティ・信頼性・運用

- 外部入力をschema validationし、D1 queryはDrizzleまたはprepared statementで実行する。
- sort、facet、target typeはallow-listに限定する。
- 公開検索はIP、認証・mutationはユーザーとIPを単位にrate limitする。
- CSP、HSTS、Referrer-Policy、X-Content-Type-Options、Permissions-Policyを設定する。
- token、email、生の検索語をログへ残さない。
- snapshot importとwrite APIは一意制約とidempotencyで再実行可能にする。
- D1の実行時間、`rows_read`、`rows_written`、認証失敗、同期件数、同期失敗を構造化ログとメトリクスで確認する。
- local、staging、productionでD1 bindingとsecretsを分離する。
- 本番は初回投入量と日次上限を考慮してWorkers Paidを前提とする。[D1料金](https://developers.cloudflare.com/d1/platform/pricing/)

## 10. テスト計画

### 10.1 Rails exporter

- canonical UUID／codeが安定して出力される。
- 全関連テーブルの追加、更新、削除、非公開化が反映される。
- manifestの件数とchecksumが実ファイルに一致する。
- 欠損参照や重複IDを検出する。
- 同じ入力から同じ論理内容を再生成できる。
- raw payload、Cookie、token、ユーザー情報が含まれない。
- 配信日の正常、単一トラック、同数日付、部分取得、degraded、failed、明示的取消を区別して出力する。

### 10.2 D1 importer

- 初回完全投入と同一snapshotの再投入が成功する。
- checksum不一致、途中失敗、参照切れではactive世代を変更しない。
- 世代切替後に検索結果が一括で新世代へ変わる。
- 直前世代へ復帰できる。
- カタログ切替後もユーザー、ブックマーク、いいねが保持される。
- failed／degradedの新観測で既知の推定配信日を消さない。

### 10.3 検索

- サークル、アルバム、楽曲、原作、原曲から検索できる。
- 日本語の表記揺れ、全半角、かな、英字大小文字を吸収する。
- 1～2文字検索と3文字以上のtrigram検索が期待どおり動く。
- FTS予約記号を含む入力でSQL errorにならない。
- 同一facet内OR、facet間ANDが全組み合わせで成立する。
- cursor paginationで重複と欠落がない。
- 配信年facetと推定配信日順が正しく、日付不明は末尾になる。

### 10.4 認証・ユーザー機能

- 匿名ユーザーが全公開ページを閲覧できる。
- 匿名mutationは401になる。
- Google callbackの正常系、state不一致、session失効を検証する。
- 他ユーザーのブックマーク・いいねを変更できない。
- bookmark／likeのPUTとDELETEが冪等に動く。
- 公開いいね数と本人状態が一致する。
- 非公開化された対象をマイページで「公開終了」と表示できる。

### 10.5 UI・公開情報

- アルバムでは「配信開始日（推定）」と表示される。
- 楽曲では収録アルバムの日付であることが分かる。
- 日付コンポーネント、tooltip、aria-label、公開JSONに日付の出典名が混入しない。
- 配信サービス一覧にはYouTube Musicの配信状況とリンクが残る。
- ハートの成功、失敗時rollback、連打、キーボード操作を検証する。
- `prefers-reduced-motion` では不要なアニメーションを行わない。
- 認証済み・個人化レスポンスが共有cacheに入らない。

## 11. 実装順序

1. データ、ジャケット、推定配信日の来歴と再公開条件を棚卸しする。
2. 新しいCloudflareアプリを別リポジトリに作成し、local／staging／production環境を定義する。
3. React Router v8、D1、Drizzle、Better Auth、Google callbackのstaging spikeを完了する。
4. Railsのversioned exporterとcontract testを実装する。
5. D1 schema、importer、世代切替、復旧手順を実装する。
6. 検索projection、FTS5、facet、詳細ページを実装する。
7. 推定配信日の表示、並び替え、配信年facetを実装する。
8. Google認証、ブックマーク、いいね、マイページを実装する。
9. アクセシビリティ、セキュリティヘッダー、rate limit、観測を追加する。
10. 実データ規模でstaging検証し、権利確認と運用手順の完了後に本番公開する。

## 12. 前提と公開ゲート

- 対象は東方同人音楽流通で配信されている作品とする。
- 現在の約3,774アルバム、約36,125楽曲を初期規模として設計する。
- ジャケットは利用条件を確認できた提供元画像だけを帰属・リンク付きで使い、確認できない場合はプレースホルダーを表示する。
- 東方Projectの非公式ファンサイトであることを明示し、[東方Project二次創作ガイドライン](https://touhou-project.news/guideline/)に従う。
- 新アプリの本番ホスト名は環境変数 `APP_ORIGIN` で与え、Google callbackとcanonical URLの単一の正本にする。
- データ、画像、推定配信日の再公開条件が確認できるまではproduction公開しない。
