# Spotify OAuth・プレイリスト系 SpotifyApi 移行 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ユーザー OAuth とプレイリスト操作を `RSpotify::*` から自前クライアント `SpotifyApi::*` へ移行し、移行過程で判明した実バグを修正してデッドコードを撤去する。

**Architecture:** `SpotifyApi::UserSession`（トークン管理・Redis 書き戻し）と `SpotifyApi::Playlist`（プレイリスト CRUD）は既に実装済み・テスト済みで本番未使用のため、本作業の大半は呼び出し先の差し替えである。唯一の新規実装は OmniAuth の Spotify ストラテジ（現在 `rspotify/oauth` に依存）。あわせて 6 箇所にコピペされたセッション取得を `before_action` に集約し、5 箇所に重複したリトライ実装を `SpotifyRetry.with_retry` に統合する。

**Tech Stack:** Rails 8.1 / Ruby（`.ruby-version` 準拠）/ minitest / RuboCop / Faraday 2 / Redis / devbox

**設計書:** `docs/superpowers/specs/2026-07-26-spotify-oauth-playlist-migration-design.md`

## Global Constraints

- すべてのコマンドは devbox 経由で実行する（`make ...` または `devbox run -- ...`）。
- テスト: `make minitest`（全体） / `devbox run -- bin/rails test <path>`（個別）。
- Lint: `make rubocop`。**全タスクで 0 offenses を維持する**（pre-commit フックで自動実行される）。
- コミットメッセージは**日本語**。`feat:` 等の英語プレフィックスは付けない（本リポジトリの既存慣習）。
- コミットに `Generated with Claude Code` / `Co-Authored-By: Claude` を**含めない**。
- ファイル作成は Write ツール、編集は Edit ツール、読み取りは Read ツールを使う（`cat` / `sed` / `echo` を使わない）。
- **機密情報を git に入れない**: アクセストークン、リフレッシュトークン、実在のメールアドレス、`account_id`、実在のプレイリスト名。VCR カセットは `.gitignore` 対象。コミットする fixture は合成値のみ（トークンは `<REDACTED>`、メールは `test@example.com`、ユーザー ID は `test-user`）。
- **原曲名に一致するプレイリストのみを読み書きする。** 判定は `OriginalSong` のクラスメソッド 1 箇所に集約し、読み取り経路と書き込み経路で同じ判定を使う。
- 作業ブランチ: `feature/spotify-oauth-playlist-migration`（作成済み）。
- 作業用ディレクトリ（スナップショット・検証スクリプト置き場、リポジトリ外）:
  `/private/tmp/claude-501/-Users-shiroemons-src-github-com-shiroemons-touhou-music-discover/6cb9ebe7-7c9e-4c11-a36c-4082e2014c81/scratchpad`
  以降このパスを `$SCRATCH` と表記する。

## 実測で確定済みの前提（再確認不要）

| 事実 | 値 |
|---|---|
| `GET /me` が返すキー | `account_id` / `display_name` / `email` / `external_urls` / `followers` / `href` / `id` / `images` / `type` / `uri` |
| `GET /me/playlists` の item が持つキー | `collaborative` / `description` / `external_urls` / `href` / `id` / `images` / `items` / `name` / `owner` / `primary_color` / `public` / `snapshot_id` / `tracks` / `type` / `uri`（**`followers` は無い**、`tracks.total` は有る） |
| `GET /playlists/{id}` が返すキー | 上記 + `followers`（`{"href" => nil, "total" => n}`） |
| `/playlists/{id}/tracks` と `/playlists/{id}/items` | どちらも 200。レスポンス一致。item は `track` と `item` の両キーを持つ |
| 対象ユーザーのプレイリスト | 613 件、612 件が原曲名に一致、全件 `public: true` |
| `OriginalSong` の title | 全体 691 種、`non_duplicated` 673 種。基準を `non_duplicated` に統一しても**落ちるプレイリストは 0 件**（実測済み） |
| `SpotifyApi::Response` | `[]` / `key?` / `to_h` / `as_json` / `method_missing` はあるが **`dig` が無い** |

## File Structure

| ファイル | 責務 | 操作 |
|---|---|---|
| `Gemfile` | `webmock` / `vcr` / `omniauth-oauth2` 追加、`spotify-client` 削除 | 変更 |
| `.gitignore` | VCR カセットを除外 | 変更 |
| `test/test_helper.rb` | WebMock / VCR の初期化 | 変更 |
| `test/support/spotify_api_stubs.rb` | Spotify HTTP スタブのヘルパ | 新規 |
| `test/fixtures/files/spotify_api/*.json` | 合成値の API レスポンス fixture | 新規 |
| `app/models/original_song.rb` | 原曲名プレイリストの判定を一元化 | 変更 |
| `lib/spotify_api/response.rb` | `dig` の追加 | 変更 |
| `lib/omniauth/strategies/spotify.rb` | OmniAuth Spotify ストラテジ | 新規 |
| `config/initializers/omniauth.rb` | 自前ストラテジの読み込みと scope | 変更 |
| `app/models/user.rb` | auth_hash からの User 生成（nil ガード・既存更新） | 変更 |
| `app/controllers/sessions_controller.rb` | auth_hash の Redis 保存（prefix・TTL） | 変更 |
| `lib/spotify_api/user_session.rb` | Redis キーの組み立てを共通化 | 変更 |
| `app/controllers/concerns/spotify_authentication.rb` | `before_action` によるセッション解決 | 新規 |
| `app/controllers/spotify/playlists_controller.rb` | 7 アクションの差し替え | 変更 |
| `app/services/spotify/playlist_update_service.rb` | プレイリスト更新サービスの差し替え | 変更 |
| `config/routes.rb` | `playlists/create` を POST 限定に | 変更 |
| `app/views/spotify/playlists/index.html.erb` | `turbo_method: :delete` 修正 | 変更 |
| `app/services/spotify_web_api/client.rb` ほか | デッドコード撤去 | 削除 |

---

### Task 1: 移行前スナップショットの取得

**目的:** 移行の前後で `SpotifyPlaylist` と Redis の状態が意図せず変わっていないことを後で検証できるようにする。**コード変更は一切行わない。** 以降のどのタスクよりも先に実施する。

**Files:**
- Create: `$SCRATCH/snapshot.rb`（リポジトリ外）
- Create: `$SCRATCH/before/`（出力先、リポジトリ外）

- [ ] **Step 1: スナップショット取得スクリプトを書く**

`$SCRATCH/snapshot.rb` を Write ツールで作成する。

```ruby
# 移行前後で比較するためのスナップショット。リポジトリには含めない。
require 'json'

dir = ENV.fetch('SNAPSHOT_DIR')
FileUtils.mkdir_p(dir)

playlists = SpotifyPlaylist.order(:spotify_id).map do |p|
  {
    spotify_id: p.spotify_id,
    spotify_user_id: p.spotify_user_id,
    name: p.name,
    original_song_code: p.original_song_code,
    total: p.total,
    followers: p.followers,
    position: p.position,
    spotify_url: p.spotify_url,
    synced_at: p.synced_at&.iso8601
  }
end
File.write(File.join(dir, 'spotify_playlists.json'), JSON.pretty_generate(playlists))

redis_dump = {}
RedisPool.with do |r|
  r.keys('*').sort.each do |k|
    redis_dump[k] = { 'type' => r.type(k), 'ttl' => r.ttl(k) }
  end
end
File.write(File.join(dir, 'redis_keys.json'), JSON.pretty_generate(redis_dump))

users = User.order(:created_at).map do |u|
  { provider: u.provider, uid: u.uid, nickname: u.nickname, name: u.name,
    email_present: u.email.present?, image_url_present: u.image_url.present? }
end
File.write(File.join(dir, 'users.json'), JSON.pretty_generate(users))

puts "playlists=#{playlists.size} redis_keys=#{redis_dump.size} users=#{users.size}"
puts "wrote to #{dir}"
```

Redis のダンプで**値そのものを保存しない**こと（アクセストークンが含まれるため）。キー名・型・TTL のみ記録する。

- [ ] **Step 2: スナップショットを取得する**

Run: `SNAPSHOT_DIR=$SCRATCH/before devbox run -- bin/rails runner $SCRATCH/snapshot.rb`

Expected: `playlists=<n> redis_keys=<n> users=1` と出力され、`$SCRATCH/before/` に 3 ファイルができる。

- [ ] **Step 3: git の作業ツリーが汚れていないことを確認する**

Run: `git status --short`

Expected: 出力が空（スナップショットはリポジトリ外に書いたため）。空でなければスクリプトの出力先が誤っているので修正する。

このタスクにコミットは無い。

---

### Task 2: テスト基盤（webmock + VCR）の導入

**目的:** 未スタブの HTTP 呼び出しでテストが即座に落ちるようにし、テストが誤って実 API を叩いてクォータを消費したり実プレイリストを変更する事故を構造的に防ぐ。

**Files:**
- Modify: `Gemfile`
- Modify: `.gitignore`
- Modify: `test/test_helper.rb`
- Create: `test/support/spotify_api_stubs.rb`

**Interfaces:**
- Produces: `SpotifyApiStubs` モジュール（`ActiveSupport::TestCase` に include 済み）
  - `spotify_fixture(name) -> String`（JSON 文字列）
  - `stub_spotify_get(path, body:, status: 200, query: nil) -> WebMock::RequestStub`
  - `stub_spotify_post(path, body:, status: 200) -> WebMock::RequestStub`
  - `stub_spotify_put(path, body:, status: 200) -> WebMock::RequestStub`
  - `stub_spotify_delete(path, body:, status: 200) -> WebMock::RequestStub`
  - `stub_spotify_token_refresh(access_token: 'NEW_TOKEN', expires_in: 3600) -> WebMock::RequestStub`

- [ ] **Step 1: Gemfile に webmock と vcr を追加する**

`Gemfile` の `group :development, :test do` ブロック内、`minitest` の行の後に追加する。

```ruby
group :development, :test do
  gem 'brakeman', require: false
  gem 'bundler-audit', require: false
  gem 'debug'
  gem 'dotenv-rails'
  gem 'minitest', '~> 6.0'
  gem 'vcr', require: false
  gem 'webmock', require: false
end
```

- [ ] **Step 2: bundle install を実行する**

Run: `devbox run -- bundle install`

Expected: `webmock` と `vcr` が追加され、`Gemfile.lock` が更新される。

- [ ] **Step 3: .gitignore に VCR カセットを追加する**

`.gitignore` の末尾に追記する。

```
# VCR カセットは実アクセストークン・メールアドレス・実プレイリスト名を含むため
# リポジトリに含めない。fixture は test/fixtures/files/spotify_api/ に合成値で置く。
/test/vcr_cassettes/
```

- [ ] **Step 4: test_helper.rb に WebMock と VCR を設定する**

`test/test_helper.rb` を以下の内容に書き換える。

```ruby
# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'
require 'webmock/minitest'
require 'vcr'

# テストから実 Spotify API を叩くとクォータを消費し、実プレイリストを壊しうる。
# 未スタブのリクエストはすべて例外にして構造的に防ぐ。
WebMock.disable_net_connect!(allow_localhost: true)

# VCR は「実 API のレスポンス形状を起こす」ローカル専用ツール。
# カセットは .gitignore 対象で、コミット済みのテストはどれもカセットに依存しない。
VCR.configure do |config|
  config.cassette_library_dir = Rails.root.join('test/vcr_cassettes').to_s
  config.hook_into :webmock
  config.default_cassette_options = { record: :none }
  config.filter_sensitive_data('<CLIENT_ID>') { ENV.fetch('SPOTIFY_CLIENT_ID', nil) }
  config.filter_sensitive_data('<CLIENT_SECRET>') { ENV.fetch('SPOTIFY_CLIENT_SECRET', nil) }
  config.filter_sensitive_data('<ACCESS_TOKEN>') do |interaction|
    interaction.request.headers['Authorization']&.first&.sub(/\ABearer /, '')
  end
end

Dir[Rails.root.join('test/support/**/*.rb')].each { |f| require f }

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # ParallelRunner を使うコードは、テストでは常に逐次実行 (records.each) にする。
    # Parallel gem を一切呼ばないため、fork や別スレッドに起因する非決定性がなくなり、
    # 各テストが同一プロセス・同一トランザクション内で決定的に動作する。
    ParallelRunner.forced_workers = 1

    include SpotifyApiStubs
  end
end
```

- [ ] **Step 5: スタブヘルパを作成する**

`test/support/spotify_api_stubs.rb` を Write ツールで作成する。

```ruby
# frozen_string_literal: true

# Spotify Web API を WebMock でスタブするためのヘルパ。
#
# fixture は test/fixtures/files/spotify_api/ に置いた合成値の JSON。
# 実 API のレスポンス形状に合わせてあるが、トークン・メールアドレス・
# プレイリスト名はすべて架空の値に置き換えてある。
module SpotifyApiStubs
  API_BASE = 'https://api.spotify.com/v1'
  ACCOUNTS_BASE = 'https://accounts.spotify.com'
  JSON_HEADERS = { 'Content-Type' => 'application/json' }.freeze

  def spotify_fixture(name)
    Rails.root.join("test/fixtures/files/spotify_api/#{name}.json").read
  end

  def spotify_fixture_hash(name)
    JSON.parse(spotify_fixture(name))
  end

  def stub_spotify_get(path, body:, status: 200, query: nil)
    stub = stub_request(:get, "#{API_BASE}/#{path}")
    stub = stub.with(query:) if query
    stub.to_return(status:, body: normalize_body(body), headers: JSON_HEADERS)
  end

  def stub_spotify_post(path, body: {}, status: 200)
    stub_request(:post, "#{API_BASE}/#{path}")
      .to_return(status:, body: normalize_body(body), headers: JSON_HEADERS)
  end

  def stub_spotify_put(path, body: {}, status: 200)
    stub_request(:put, "#{API_BASE}/#{path}")
      .to_return(status:, body: normalize_body(body), headers: JSON_HEADERS)
  end

  def stub_spotify_delete(path, body: {}, status: 200)
    stub_request(:delete, "#{API_BASE}/#{path}")
      .to_return(status:, body: normalize_body(body), headers: JSON_HEADERS)
  end

  # 429 応答。Retry-After を秒で指定する。
  def stub_spotify_rate_limited(method, path, retry_after: 1)
    stub_request(method, "#{API_BASE}/#{path}")
      .to_return(status: 429, body: '{}',
                 headers: JSON_HEADERS.merge('Retry-After' => retry_after.to_s))
  end

  def stub_spotify_token_refresh(access_token: 'NEW_ACCESS_TOKEN', expires_in: 3600)
    stub_request(:post, "#{ACCOUNTS_BASE}/api/token")
      .to_return(status: 200,
                 body: { access_token:, token_type: 'Bearer', expires_in: }.to_json,
                 headers: JSON_HEADERS)
  end

  private

  def normalize_body(body)
    body.is_a?(String) ? body : body.to_json
  end
end
```

- [ ] **Step 6: 既存テストが全て通ることを確認する**

Run: `make minitest`

Expected: 458 runs, 0 failures, 0 errors。**ここで失敗した場合は、そのテストが実ネットワークを叩いていたということ**なので、原因のテストを特定して報告する（勝手に `allow_net_connect` を緩めない）。

- [ ] **Step 7: RuboCop を通す**

Run: `make rubocop`

Expected: 0 offenses。

- [ ] **Step 8: コミット**

```bash
git add Gemfile Gemfile.lock .gitignore test/test_helper.rb test/support/spotify_api_stubs.rb
git commit -m "テストで実 Spotify API を叩けないようにする

- webmock を導入し disable_net_connect! で未スタブのリクエストを例外にする
- vcr を導入（実 API のレスポンス形状を起こすローカル専用ツール）
- VCR カセットはトークンと個人情報を含むため .gitignore 対象にする
- Spotify HTTP スタブのヘルパ SpotifyApiStubs を追加"
```

---

### Task 3: 原曲名プレイリストの判定を一元化する

**目的:** 「原曲名に一致するプレイリストのみ読み書きする」という保証の判定を 1 箇所に集約する。現状は `index` が `OriginalSong.distinct.pluck(:title)`（重複曲を含む 691 種）、`find_original_song_code` が `is_duplicate: false`（673 種）と**基準が食い違っている**。

**Files:**
- Modify: `app/models/original_song.rb`
- Modify: `app/controllers/spotify/playlists_controller.rb:41-42, 548-552`
- Test: `test/models/original_song_test.rb`（新規作成）

**Interfaces:**
- Produces:
  - `OriginalSong.playlist_titles -> Array<String>`（重複曲を除いた title の一覧）
  - `OriginalSong.playlist_title?(title) -> Boolean`
  - `OriginalSong.playlist_code_for(title) -> String | nil`
  - `OriginalSong.playlist_code_map -> Hash{String => String}`（title => code。N+1 回避用）

**基準統一の安全性:** 実測で「重複曲としてのみ存在する title」は 18 種あるが、そのいずれの名前のプレイリストも存在しない。基準を `non_duplicated` に統一しても落ちるプレイリストは 0 件であることを確認済み。

- [ ] **Step 1: 失敗するテストを書く**

`test/models/original_song_test.rb` を Write ツールで作成する。

```ruby
# frozen_string_literal: true

require 'test_helper'

class OriginalSongTest < ActiveSupport::TestCase
  test 'playlist_titles excludes duplicated songs' do
    original = Original.create!(code: 'TEST_ORIG', title: 'テスト作品', original_type: :windows,
                                series_order: 9999)
    OriginalSong.create!(code: 'TEST_S1', original_code: original.code, title: 'ユニーク原曲',
                         track_number: 1, is_duplicate: false)
    OriginalSong.create!(code: 'TEST_S2', original_code: original.code, title: '重複のみ原曲',
                         track_number: 2, is_duplicate: true)

    titles = OriginalSong.playlist_titles

    assert_includes titles, 'ユニーク原曲'
    assert_not_includes titles, '重複のみ原曲'
  end

  test 'playlist_title? mirrors playlist_titles' do
    original = Original.create!(code: 'TEST_ORIG2', title: 'テスト作品2', original_type: :windows,
                                series_order: 9998)
    OriginalSong.create!(code: 'TEST_S3', original_code: original.code, title: '判定対象原曲',
                         track_number: 1, is_duplicate: false)

    assert OriginalSong.playlist_title?('判定対象原曲')
    assert_not OriginalSong.playlist_title?('存在しないプレイリスト名')
  end

  test 'playlist_code_for returns the code of a non-duplicated song' do
    original = Original.create!(code: 'TEST_ORIG3', title: 'テスト作品3', original_type: :windows,
                                series_order: 9997)
    OriginalSong.create!(code: 'TEST_S4', original_code: original.code, title: 'コード引き原曲',
                         track_number: 1, is_duplicate: false)

    assert_equal 'TEST_S4', OriginalSong.playlist_code_for('コード引き原曲')
    assert_nil OriginalSong.playlist_code_for('存在しないプレイリスト名')
  end

  test 'playlist_code_map maps titles to codes without duplicated songs' do
    original = Original.create!(code: 'TEST_ORIG4', title: 'テスト作品4', original_type: :windows,
                                series_order: 9996)
    OriginalSong.create!(code: 'TEST_S5', original_code: original.code, title: 'マップ原曲',
                         track_number: 1, is_duplicate: false)
    OriginalSong.create!(code: 'TEST_S6', original_code: original.code, title: 'マップ重複原曲',
                         track_number: 2, is_duplicate: true)

    map = OriginalSong.playlist_code_map

    assert_equal 'TEST_S5', map['マップ原曲']
    assert_not map.key?('マップ重複原曲')
  end
end
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `devbox run -- bin/rails test test/models/original_song_test.rb`

Expected: FAIL。`NoMethodError: undefined method 'playlist_titles' for class OriginalSong`。

- [ ] **Step 3: OriginalSong にクラスメソッドを実装する**

`app/models/original_song.rb` の `scope :non_duplicated` の行の後に追加する。

```ruby
  scope :non_duplicated, -> { where(is_duplicate: false) }

  class << self
    # このアプリが読み書きするプレイリストは「名前が原曲名に一致するもの」だけ。
    # 判定基準をここに集約し、読み取り経路と書き込み経路で必ず同じ基準を使う。
    # 重複曲 (is_duplicate) は原曲別プレイリストの対象にしないため除外する。
    def playlist_titles
      non_duplicated.distinct.pluck(:title)
    end

    def playlist_title?(title)
      return false if title.blank?

      non_duplicated.exists?(title:)
    end

    def playlist_code_for(title)
      return nil if title.blank?

      non_duplicated.find_by(title:)&.code
    end

    # プレイリストを一括処理するときに 1 件ずつ引かないための title => code マップ。
    def playlist_code_map
      non_duplicated.pluck(:title, :code).to_h
    end
  end
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `devbox run -- bin/rails test test/models/original_song_test.rb`

Expected: 4 runs, 0 failures。

- [ ] **Step 5: コントローラの既存呼び出しを差し替える**

`app/controllers/spotify/playlists_controller.rb` の `index` 内（41-42 行目）:

```ruby
      # 原曲名と一致するプレイリストのみ抽出するための処理
      original_song_titles = OriginalSong.distinct.pluck(:title)
      @playlists = @playlists.select { |p| p[:name].in?(original_song_titles) }
```

を次に置き換える。

```ruby
      # 原曲名と一致するプレイリストのみ抽出する
      original_song_titles = OriginalSong.playlist_titles
      @playlists = @playlists.select { |p| p[:name].in?(original_song_titles) }
```

`refresh_counts` 内（241-242 行目）:

```ruby
          original_song_titles = OriginalSong.distinct.pluck(:title)
          filtered_playlists = playlists.select { |p| p.name.in?(original_song_titles) }
```

を次に置き換える。

```ruby
          original_song_titles = OriginalSong.playlist_titles
          filtered_playlists = playlists.select { |p| p.name.in?(original_song_titles) }
```

private メソッド `find_original_song_code`（548-552 行目）を削除し、その呼び出し元 2 箇所
（264 行目 `original_song_code: find_original_song_code(playlist.name)` と
542 行目 `p.original_song_code = find_original_song_code(playlist[:name])`）を
`OriginalSong.playlist_code_for(...)` に置き換える。

- [ ] **Step 6: 全テストと RuboCop を通す**

Run: `make minitest && make rubocop`

Expected: 全テスト pass、0 offenses。

- [ ] **Step 7: コミット**

```bash
git add app/models/original_song.rb app/controllers/spotify/playlists_controller.rb test/models/original_song_test.rb
git commit -m "原曲名プレイリストの判定を OriginalSong に集約する

- index は重複曲を含む title で絞り込み、原曲コード引きは重複曲を除外していて
  基準が食い違っていたため non_duplicated に統一する
- 実測で、統一によって除外されるプレイリストが 0 件であることを確認済み
- playlist_titles / playlist_title? / playlist_code_for / playlist_code_map を追加"
```

---

### Task 4: `SpotifyApi::Response#dig` を追加する

**目的:** `Page#items` は各要素を `Response` に包むため、移行後のコードが `p.dig('tracks', 'total')` で `NoMethodError` を踏む（実測で確認済み）。

**Files:**
- Modify: `lib/spotify_api/response.rb`
- Test: `test/lib/spotify_api/response_test.rb`

**Interfaces:**
- Produces: `SpotifyApi::Response#dig(*keys) -> Object | nil`（キーは文字列・シンボルどちらでも可。戻り値は生の値）

- [ ] **Step 1: 失敗するテストを書く**

`test/lib/spotify_api/response_test.rb` の末尾（クラス内）に追加する。

```ruby
    test 'dig walks nested hashes with string or symbol keys' do
      response = Response.build({ 'tracks' => { 'total' => 12 }, 'name' => 'Playlist' })

      assert_equal 12, response.dig('tracks', 'total')
      assert_equal 12, response.dig(:tracks, :total)
      assert_equal 'Playlist', response.dig('name')
    end

    test 'dig returns nil for missing keys instead of raising' do
      response = Response.build({ 'tracks' => { 'total' => 12 } })

      assert_nil response.dig('followers', 'total')
      assert_nil response.dig('tracks', 'missing')
    end
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `devbox run -- bin/rails test test/lib/spotify_api/response_test.rb`

Expected: FAIL。`NoMethodError: undefined method 'dig' for an instance of SpotifyApi::Response`。

- [ ] **Step 3: dig を実装する**

`lib/spotify_api/response.rb` の `key?` メソッドの後に追加する。

```ruby
    def key?(key)
      data.key?(key.to_s)
    end

    # ネストした値を辿る。Page#items は各要素を Response に包むため、
    # playlist.dig('tracks', 'total') のような書き方が呼び出し側で必要になる。
    # キーが無い場合は Hash#dig と同じく nil を返す。
    def dig(*keys)
      data.dig(*keys.map(&:to_s))
    end
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `devbox run -- bin/rails test test/lib/spotify_api/response_test.rb`

Expected: 全 test pass。

- [ ] **Step 5: RuboCop を通してコミット**

Run: `make rubocop`

```bash
git add lib/spotify_api/response.rb test/lib/spotify_api/response_test.rb
git commit -m "SpotifyApi::Response に dig を追加する

Page#items は各要素を Response に包むため、playlist.dig('tracks', 'total') の
ような呼び出しが必要になるが、Response は dig を実装していなかった。"
```

---

### Task 5: OmniAuth Spotify ストラテジを自前実装する

**目的:** `require 'rspotify/oauth'` への依存を断ち、scope から未使用の権限を外す。

**Files:**
- Create: `lib/omniauth/strategies/spotify.rb`
- Modify: `Gemfile`
- Modify: `config/initializers/omniauth.rb`
- Test: `test/lib/omniauth/strategies/spotify_test.rb`

**Interfaces:**
- Produces: `OmniAuth::Strategies::Spotify`
  - `#uid -> String`（`raw_info['id']`）
  - `#info -> Hash`（キー: `:id` / `:display_name` / `:name` / `:nickname` / `:email` / `:images` / `:external_urls` / `:followers` / `:href` / `:uri`）
  - `#extra -> Hash`（`{ raw_info: Hash }`）

**重要:** `app/models/user.rb` は `auth_hash[:info][:images][0][:url]` と `auth_hash[:info][:display_name]` と `auth_hash[:info][:id]` を読む。**`images` は配列のまま、`display_name` と `id` はそのままのキー名で渡すこと。** Task 6 で nil ガードを入れるが、キー構造自体は変えない。

- [ ] **Step 1: Gemfile に omniauth-oauth2 を明示追加する**

現在 `omniauth` / `omniauth-oauth2` は rspotify 経由の推移的依存で、rspotify を外した瞬間に無言で壊れる。`Gemfile` の `gem 'omniauth-rails_csrf_protection', '~> 2.0'` の行の直前に追加する。

```ruby
gem 'omniauth-oauth2', '~> 1.9'
gem 'omniauth-rails_csrf_protection', '~> 2.0'
```

Run: `devbox run -- bundle install`

Expected: `Gemfile.lock` の DEPENDENCIES に `omniauth-oauth2 (~> 1.9)` が追加される。

- [ ] **Step 2: 失敗するテストを書く**

`test/lib/omniauth/strategies/spotify_test.rb` を Write ツールで作成する。

```ruby
# frozen_string_literal: true

require 'test_helper'

module OmniAuth
  module Strategies
    class SpotifyTest < ActiveSupport::TestCase
      # GET /v1/me の実レスポンス形状（値はすべて架空）
      RAW_INFO = {
        'account_id' => 'ACCOUNT123',
        'display_name' => 'Test User',
        'email' => 'test@example.com',
        'external_urls' => { 'spotify' => 'https://open.spotify.com/user/test-user' },
        'followers' => { 'href' => nil, 'total' => 3 },
        'href' => 'https://api.spotify.com/v1/users/test-user',
        'id' => 'test-user',
        'images' => [{ 'height' => 300, 'url' => 'https://example.test/avatar.png', 'width' => 300 }],
        'type' => 'user',
        'uri' => 'spotify:user:test-user'
      }.freeze

      def build_strategy(raw_info = RAW_INFO)
        strategy = Spotify.new(nil, 'client-id', 'client-secret')
        strategy.define_singleton_method(:raw_info) { raw_info }
        strategy
      end

      test 'uid comes from the Spotify user id' do
        assert_equal 'test-user', build_strategy.uid
      end

      test 'info keeps the keys app/models/user.rb reads' do
        info = build_strategy.info

        assert_equal 'test-user', info[:id]
        assert_equal 'Test User', info[:display_name]
        assert_equal 'test@example.com', info[:email]
        assert_equal 'https://example.test/avatar.png', info[:images][0][:url]
      end

      test 'info tolerates a user without images or email' do
        info = build_strategy(RAW_INFO.merge('images' => [], 'email' => nil)).info

        assert_equal [], info[:images]
        assert_nil info[:email]
      end

      test 'extra carries the raw payload' do
        assert_equal RAW_INFO, build_strategy.extra[:raw_info]
      end

      test 'client options point at the Spotify accounts service' do
        options = Spotify.new(nil, 'client-id', 'client-secret').options.client_options

        assert_equal 'https://accounts.spotify.com', options[:site]
        assert_equal '/authorize', options[:authorize_url]
        assert_equal '/api/token', options[:token_url]
      end
    end
  end
end
```

- [ ] **Step 3: テストが失敗することを確認する**

Run: `devbox run -- bin/rails test test/lib/omniauth/strategies/spotify_test.rb`

Expected: FAIL。`NameError: uninitialized constant OmniAuth::Strategies::Spotify`（rspotify 由来のものが読み込まれていれば別のエラーになる。その場合も次のステップで自前実装に差し替わる）。

- [ ] **Step 4: ストラテジを実装する**

`lib/omniauth/strategies/spotify.rb` を Write ツールで作成する。

```ruby
# frozen_string_literal: true

require 'omniauth-oauth2'

module OmniAuth
  module Strategies
    # Spotify の Authorization Code フロー用 OmniAuth ストラテジ。
    #
    # 以前は rspotify gem 同梱の 'rspotify/oauth' を使っていたが、rspotify は
    # Issue #563 で削除予定であり、また RSpotify::User がトークンをプロセス
    # グローバルなクラス変数に持つ設計を引き継ぎたくないため自前で実装する。
    #
    # info のキー構造は app/models/user.rb が読む形（display_name / id / email /
    # images の配列）を保つこと。ここを変えると既存ユーザーの取り込みが壊れる。
    class Spotify < OmniAuth::Strategies::OAuth2
      option :name, 'spotify'

      option :client_options,
             site: 'https://accounts.spotify.com',
             authorize_url: '/authorize',
             token_url: '/api/token'

      uid { raw_info['id'] }

      info do
        {
          id: raw_info['id'],
          display_name: raw_info['display_name'],
          name: raw_info['display_name'],
          nickname: raw_info['display_name'],
          email: raw_info['email'],
          images: raw_info['images'] || [],
          external_urls: raw_info['external_urls'],
          followers: raw_info['followers'],
          href: raw_info['href'],
          uri: raw_info['uri']
        }
      end

      extra do
        { raw_info: }
      end

      def raw_info
        @raw_info ||= access_token.get('v1/me').parsed
      end

      # OmniAuth 2 系では callback_url に query string が含まれるとトークン交換で
      # redirect_uri 不一致になるため、query を落とす。
      def callback_url
        full_host + callback_path
      end
    end
  end
end

OmniAuth.config.add_camelization('spotify', 'Spotify')
```

`info` の `images` は Hash の配列（キーは文字列）。テストは `info[:images][0][:url]` を
シンボルで引いているが、OmniAuth の `AuthHash` は `Hashie::Mash` 由来で文字列・シンボルの
どちらでも引ける。テストが `info` を素の Hash として受けて落ちる場合は、テスト側を
`info[:images][0]['url']` に直すこと（実装側で `images` の中身を変換しない — 実 API の
形状をそのまま `raw_info` として保つほうが後の調査で嘘をつかない）。

- [ ] **Step 5: initializer を差し替える**

`config/initializers/omniauth.rb` を以下の内容に書き換える。

```ruby
# frozen_string_literal: true

require 'omniauth'
require Rails.root.join('lib/omniauth/strategies/spotify')

# OmniAuth 2.0以降のCSRF対策設定
OmniAuth.config.allowed_request_methods = %i[post]

# scope は必要最小限にする。
# - user-read-email: users.email に使用（GET /me は 2026-07 時点でも email を返す）
# - playlist-modify-public: プレイリストの作成・差し替えに必要
# 以前指定していた user-library-read / user-library-modify は保存済みライブラリ
# (GET /me/albums 等) の権限で、本アプリでは一度も使っていないため外した。
# playlist-read-private は対象プレイリストが全件 public のため付けない。
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :spotify,
           ENV.fetch('SPOTIFY_CLIENT_ID', nil),
           ENV.fetch('SPOTIFY_CLIENT_SECRET', nil),
           scope: 'user-read-email playlist-modify-public'
end
```

- [ ] **Step 6: テストが通ることを確認する**

Run: `devbox run -- bin/rails test test/lib/omniauth/strategies/spotify_test.rb`

Expected: 5 runs, 0 failures。

- [ ] **Step 7: アプリが起動し、ストラテジが登録されていることを確認する**

Run: `devbox run -- bin/rails runner 'puts OmniAuth::Strategies::Spotify.name; puts OmniAuth::Strategies::Spotify.default_options[:client_options].to_h.inspect'`

Expected: `OmniAuth::Strategies::Spotify` と `{"site" => "https://accounts.spotify.com", "authorize_url" => "/authorize", "token_url" => "/api/token"}` 相当が出力される。rspotify 側の定数が先に読まれていると別の結果になるので、その場合は報告する。

- [ ] **Step 8: 全テストと RuboCop を通してコミット**

Run: `make minitest && make rubocop`

```bash
git add Gemfile Gemfile.lock lib/omniauth/strategies/spotify.rb config/initializers/omniauth.rb test/lib/omniauth/strategies/spotify_test.rb
git commit -m "OmniAuth の Spotify ストラテジを自前実装する

- rspotify/oauth への依存を断つ（rspotify は #563 で削除予定）
- omniauth-oauth2 を Gemfile に明示追加（従来は rspotify 経由の推移的依存）
- scope から未使用の user-library-read / user-library-modify を削除
- user-read-email は実 API で email が返ることを確認済みのため残す
- info のキー構造は app/models/user.rb が読む形をそのまま保つ"
```

**注意:** この時点で scope が変わったため、**次にログインするときに Spotify の再認可画面が出る**。既存の Redis 上の auth_hash はまだ有効なので、既存機能はそのまま動く。

---

### Task 6: `User` の nil ガードと既存ユーザー更新バグの修正

**目的:** 画像 0 件のユーザーで `NoMethodError` になる穴を塞ぎ、既存ユーザーの属性が永久に更新されないバグを直す。

**Files:**
- Modify: `app/models/user.rb`
- Test: `test/models/user_test.rb`

**Interfaces:**
- Consumes: Task 5 の `OmniAuth::Strategies::Spotify#info` のキー構造
- Produces: `User.find_or_create_from_auth_hash(auth_hash) -> User`（既存ユーザーの場合は属性を更新して返す）

- [ ] **Step 1: 失敗するテストを書く**

`test/models/user_test.rb` を以下の内容で書き換える。

```ruby
# frozen_string_literal: true

require 'test_helper'

class UserTest < ActiveSupport::TestCase
  def auth_hash(overrides = {})
    base = {
      provider: 'spotify',
      uid: 'test-user',
      info: {
        id: 'test-user',
        display_name: 'Test User',
        email: 'test@example.com',
        images: [{ 'url' => 'https://example.test/avatar.png' }]
      }
    }
    base[:info] = base[:info].merge(overrides.delete(:info) || {})
    base.merge(overrides)
  end

  test 'creates a user from the auth hash' do
    user = User.find_or_create_from_auth_hash(auth_hash)

    assert_equal 'spotify', user.provider
    assert_equal 'test-user', user.uid
    assert_equal 'Test User', user.nickname
    assert_equal 'test-user', user.name
    assert_equal 'test@example.com', user.email
    assert_equal 'https://example.test/avatar.png', user.image_url
  end

  test 'updates attributes of an existing user' do
    User.find_or_create_from_auth_hash(auth_hash)

    updated = User.find_or_create_from_auth_hash(
      auth_hash(info: { display_name: 'Renamed User',
                        images: [{ 'url' => 'https://example.test/new.png' }] })
    )

    assert_equal 1, User.where(provider: 'spotify', uid: 'test-user').count
    assert_equal 'Renamed User', updated.nickname
    assert_equal 'https://example.test/new.png', updated.image_url
  end

  test 'tolerates a user without a profile image' do
    user = User.find_or_create_from_auth_hash(auth_hash(info: { images: [] }))

    assert_equal '', user.image_url
  end

  test 'tolerates a missing images key' do
    hash = auth_hash
    hash[:info].delete(:images)

    user = User.find_or_create_from_auth_hash(hash)

    assert_equal '', user.image_url
  end

  test 'falls back to an empty email when Spotify omits it' do
    user = User.find_or_create_from_auth_hash(auth_hash(info: { email: nil }))

    assert_equal '', user.email
  end

  test 'falls back to the Spotify id when display_name is missing' do
    user = User.find_or_create_from_auth_hash(auth_hash(info: { display_name: nil }))

    assert_equal 'test-user', user.nickname
  end
end
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `devbox run -- bin/rails test test/models/user_test.rb`

Expected: FAIL。少なくとも `updates attributes of an existing user`（既存ユーザーが更新されない）と `tolerates a user without a profile image`（`NoMethodError: undefined method '[]' for nil`）が落ちる。

- [ ] **Step 3: User を実装し直す**

`app/models/user.rb` を以下の内容に書き換える。

```ruby
# frozen_string_literal: true

class User < ApplicationRecord
  # OmniAuth の auth_hash から User を作成または更新する。
  #
  # Spotify のプロフィールは画像が 0 件だったり email が返らないことがあるため、
  # すべて nil ガードを通す（users.email / users.image_url は null: false default ''）。
  # 属性の代入を find_or_create_by! のブロックの外に出しているのは、ブロックが
  # 新規作成時にしか実行されず、既存ユーザーの表示名や画像が永久に更新されな
  # かったため。
  def self.find_or_create_from_auth_hash(auth_hash)
    info = auth_hash[:info] || {}

    user = find_or_initialize_by(provider: auth_hash[:provider], uid: auth_hash[:uid])
    user.name = info[:id].to_s
    user.nickname = info[:display_name].presence || info[:id].to_s
    user.email = info[:email].to_s
    user.image_url = info.dig(:images, 0, :url).to_s
    user.save!
    user
  end
end
```

`info.dig(:images, 0, :url)` は、`info` が素の Hash で `images` の要素が文字列キーの場合に
nil を返してしまう。テスト `creates a user from the auth hash` は `{ 'url' => ... }` を
渡しているため、ここで落ちる場合は次のように書き換えること。

```ruby
    image = Array(info[:images]).first
    user.image_url = (image.is_a?(Hash) ? (image[:url] || image['url']) : nil).to_s
```

OmniAuth 実運用では `AuthHash`（`Hashie::Mash`）が渡るため `dig(:images, 0, :url)` で
引けるが、テストから素の Hash を渡す場合に備えて両方引けるようにしておく。

- [ ] **Step 4: テストが通ることを確認する**

Run: `devbox run -- bin/rails test test/models/user_test.rb`

Expected: 6 runs, 0 failures。

- [ ] **Step 5: 全テストと RuboCop を通してコミット**

Run: `make minitest && make rubocop`

```bash
git add app/models/user.rb test/models/user_test.rb
git commit -m "User の auth_hash 取り込みを堅牢にする

- 画像 0 件・images キー欠落・email 欠落・display_name 欠落を nil ガードする
- 属性代入を find_or_create_by! のブロック外に出し、既存ユーザーの
  nickname / email / image_url が永久に更新されなかったバグを修正する"
```

---

### Task 7: セッション解決を `before_action` に集約し、`index` / `clear_cache` を差し替える

**目的:** 6 箇所にコピペされたセッション取得を 1 箇所にまとめ、`return` 漏れによる `TypeError` を構造的に消す。`index` のリクエスト数を 625 → 13 に減らす。

**Files:**
- Create: `app/controllers/concerns/spotify_authentication.rb`
- Modify: `app/controllers/spotify/playlists_controller.rb`
- Create: `test/fixtures/files/spotify_api/me_playlists.json`
- Test: `test/controllers/spotify/playlists_controller_test.rb`

**Interfaces:**
- Consumes: `SpotifyApi::UserSession.find(user_id) -> UserSession | nil`、`SpotifyApi::Playlist.all_mine(session, limit:) -> Array<Response>`、`OriginalSong.playlist_titles`、`OriginalSong.playlist_code_map`、`SpotifyApi::Response#dig`
- Produces:
  - `SpotifyAuthentication#spotify_session -> SpotifyApi::UserSession`（private）
  - `SpotifyAuthentication#spotify_user_id -> String`（private）
  - `Spotify::PlaylistsController#fetch_playlists_from_spotify -> Array<Hash>`（引数なしに変更。要素は `{id:, name:, external_urls:, followers:, total:, synced_at:}`）
  - `Spotify::PlaylistsController#save_playlists_to_db(spotify_user_id, playlists) -> void`

- [ ] **Step 1: 認証 concern を作成する**

`app/controllers/concerns/spotify_authentication.rb` を Write ツールで作成する。

```ruby
# frozen_string_literal: true

# Spotify のユーザーセッション（アクセストークン）を解決する before_action。
#
# 従来は各アクションが以下の 3 行をコピペしていた。
#
#   redirect_to root_url unless session[:user_id]   # ← return が無い
#   auth_hash = JSON.parse(redis.get(session[:user_id]))
#   spotify_user = RSpotify::User.new(auth_hash)
#
# 1 行目に return が無いため、未ログインでもリダイレクト後に処理が続行し、
# JSON.parse(nil) が TypeError になっていた。before_action に集約することで
# この穴が構造的に消える。
module SpotifyAuthentication
  extend ActiveSupport::Concern

  private

  attr_reader :spotify_session

  def require_spotify_session
    return redirect_to root_url if session[:user_id].blank?

    @spotify_session = SpotifyApi::UserSession.find(session[:user_id])
    # セッションはあるが Redis に認証情報が無い（期限切れ・ログアウト済み）。
    # RSpotify::User のように「他のユーザーのトークン」へフォールバックしない。
    redirect_to root_url if @spotify_session.nil?
  end

  def spotify_user_id
    spotify_session.spotify_user_id
  end
end
```

- [ ] **Step 2: fixture を作成する**

`test/fixtures/files/spotify_api/me_playlists.json` を Write ツールで作成する。値はすべて架空。
形状は実 API に合わせてある（`followers` が無く `tracks.total` がある点が重要）。

```json
{
  "href": "https://api.spotify.com/v1/me/playlists?offset=0&limit=50",
  "limit": 50,
  "next": null,
  "offset": 0,
  "previous": null,
  "total": 2,
  "items": [
    {
      "collaborative": false,
      "description": "",
      "external_urls": { "spotify": "https://open.spotify.com/playlist/PL_MATCHED" },
      "href": "https://api.spotify.com/v1/playlists/PL_MATCHED",
      "id": "PL_MATCHED",
      "images": [],
      "name": "PLAYLIST_TITLE_MATCHED",
      "owner": { "id": "test-user", "type": "user" },
      "primary_color": null,
      "public": true,
      "snapshot_id": "snap1",
      "tracks": { "href": "https://api.spotify.com/v1/playlists/PL_MATCHED/tracks", "total": 7 },
      "type": "playlist",
      "uri": "spotify:playlist:PL_MATCHED"
    },
    {
      "collaborative": false,
      "description": "",
      "external_urls": { "spotify": "https://open.spotify.com/playlist/PL_UNMATCHED" },
      "href": "https://api.spotify.com/v1/playlists/PL_UNMATCHED",
      "id": "PL_UNMATCHED",
      "images": [],
      "name": "原曲名ではないプレイリスト",
      "owner": { "id": "test-user", "type": "user" },
      "primary_color": null,
      "public": true,
      "snapshot_id": "snap2",
      "tracks": { "href": "https://api.spotify.com/v1/playlists/PL_UNMATCHED/tracks", "total": 3 },
      "type": "playlist",
      "uri": "spotify:playlist:PL_UNMATCHED"
    }
  ]
}
```

`PLAYLIST_TITLE_MATCHED` はテスト内で実際の原曲名に置換して使う（後述）。

- [ ] **Step 3: 失敗するテストを書く**

`test/controllers/spotify/playlists_controller_test.rb` を以下の内容で書き換える。

```ruby
# frozen_string_literal: true

require 'test_helper'

module Spotify
  class PlaylistsControllerTest < ActionDispatch::IntegrationTest
    # Redis を共有するため、ワーカー間でキーが衝突しないよう逐次実行する。
    parallelize(workers: 1)

    setup do
      @original = Original.create!(code: 'TEST_ORIG_PC', title: 'テスト作品', original_type: :windows,
                                   series_order: 9990)
      @song = OriginalSong.create!(code: 'TEST_SONG_PC', original_code: @original.code,
                                   title: 'テスト原曲', track_number: 1, is_duplicate: false)
      @user = User.create!(provider: 'spotify', uid: 'test-user', name: 'test-user',
                           nickname: 'Test User', email: 'test@example.com', image_url: '')
      store_auth_hash
    end

    teardown do
      RedisPool.with { |r| r.del(@user.id, "playlist_update:#{@user.id}", "refresh_counts:#{@user.id}") }
    end

    def store_auth_hash(expires_at: 1.hour.from_now.to_i)
      hash = {
        'provider' => 'spotify', 'uid' => 'test-user',
        'info' => { 'id' => 'test-user', 'display_name' => 'Test User' },
        'credentials' => { 'token' => 'USER_TOKEN', 'refresh_token' => 'REFRESH_TOKEN',
                           'expires_at' => expires_at, 'expires' => true }
      }
      RedisPool.with { |r| r.set(@user.id, hash.to_json) }
    end

    def log_in
      post '/test_login', params: { user_id: @user.id }
    end

    def me_playlists_body
      spotify_fixture('me_playlists').gsub('PLAYLIST_TITLE_MATCHED', @song.title)
    end

    test 'index redirects to root when not logged in' do
      get spotify_playlists_path

      assert_redirected_to root_url
    end

    test 'index fetches playlists from Spotify and stores only original-song ones' do
      log_in
      stub = stub_spotify_get('me/playlists', body: me_playlists_body,
                              query: { 'limit' => '50', 'offset' => '0' })

      get spotify_playlists_path

      assert_response :success
      assert_requested stub
      assert_equal ['PL_MATCHED'], SpotifyPlaylist.pluck(:spotify_id)
      assert_equal @song.code, SpotifyPlaylist.first.original_song_code
      assert_equal 7, SpotifyPlaylist.first.total
    end

    test 'index does not issue per-playlist requests for follower counts' do
      log_in
      stub_spotify_get('me/playlists', body: me_playlists_body,
                       query: { 'limit' => '50', 'offset' => '0' })

      get spotify_playlists_path

      assert_response :success
      assert_not_requested :get, "#{SpotifyApiStubs::API_BASE}/playlists/PL_MATCHED"
    end

    test 'index shows follower counts from the database' do
      log_in
      SpotifyPlaylist.create!(spotify_id: 'PL_MATCHED', spotify_user_id: 'test-user',
                              name: @song.title, followers: 42, total: 7, position: 0)

      get spotify_playlists_path

      assert_response :success
      assert_equal 42, SpotifyPlaylist.find_by(spotify_id: 'PL_MATCHED').followers
      assert_not_requested :get, "#{SpotifyApiStubs::API_BASE}/me/playlists"
    end

    test 'index refreshes an expired token before calling the API' do
      log_in
      store_auth_hash(expires_at: 1.hour.ago.to_i)
      token_stub = stub_spotify_token_refresh
      stub_spotify_get('me/playlists', body: me_playlists_body,
                       query: { 'limit' => '50', 'offset' => '0' })

      get spotify_playlists_path

      assert_response :success
      assert_requested token_stub
      stored = JSON.parse(RedisPool.with { |r| r.get(@user.id) })
      assert_equal 'NEW_ACCESS_TOKEN', stored.dig('credentials', 'token')
    end

    test 'clear_cache deletes cached playlists for the user' do
      log_in
      SpotifyPlaylist.create!(spotify_id: 'PL_MATCHED', spotify_user_id: 'test-user',
                              name: @song.title, position: 0)

      delete spotify_clear_playlists_cache_path

      assert_redirected_to spotify_playlists_path
      assert_equal 0, SpotifyPlaylist.for_user('test-user').count
    end

    test 'clear_cache redirects to root when not logged in' do
      delete spotify_clear_playlists_cache_path

      assert_redirected_to root_url
    end
  end
end
```

このテストは `/test_login` というテスト専用ルートに依存する。次のステップで用意する。

- [ ] **Step 4: テスト用ログインルートを追加する**

統合テストから `session[:user_id]` を設定する手段が無いため、test 環境限定のルートを足す。
`config/routes.rb` の末尾（最後の `end` の直前）に追加する。

```ruby
  # 統合テストから session[:user_id] を設定するためのルート。test 環境限定。
  if Rails.env.test?
    post '/test_login', to: ->(env) {
      req = ActionDispatch::Request.new(env)
      req.session[:user_id] = req.params[:user_id]
      [302, { 'Location' => '/' }, []]
    }
  end
```

- [ ] **Step 5: テストが失敗することを確認する**

Run: `devbox run -- bin/rails test test/controllers/spotify/playlists_controller_test.rb`

Expected: FAIL。`index` がまだ RSpotify 経由のため、WebMock が未スタブのリクエストを
検出するか、`RSpotify::User` の初期化で落ちる。

- [ ] **Step 6: コントローラを差し替える**

`app/controllers/spotify/playlists_controller.rb` を編集する。

クラス冒頭（4-7 行目）:

```ruby
module Spotify
  class PlaylistsController < ApplicationController
    include SpotifyAuthentication

    LIMIT = 50

    before_action :require_spotify_session,
                  only: %i[index clear_cache sync_single create refresh_counts original_songs]
```

`MAX_RETRIES` と `CACHE_TTL` を削除する（`MAX_RETRIES` は `SpotifyRetry` に統合されるため。
`CACHE_TTL` は元から未使用）。

`index`（9-46 行目）を次に置き換える。

```ruby
    def index
      @from_cache = false
      @error = nil

      db_playlists = SpotifyPlaylist.for_user(spotify_user_id)
      if db_playlists.exists?
        @playlists = db_playlists.order(position: :desc).map do |playlist|
          {
            id: playlist.spotify_id,
            name: playlist.name,
            external_urls: { spotify: playlist.spotify_url },
            followers: playlist.followers,
            total: playlist.total,
            synced_at: playlist.synced_at
          }
        end
        @from_cache = true
        return
      end

      @playlists = fetch_playlists_from_spotify
      return if @error.present?

      save_playlists_to_db(spotify_user_id, @playlists) if @playlists.present?
    end
```

`clear_cache`（48-59 行目）を次に置き換える。

```ruby
    def clear_cache
      SpotifyPlaylist.for_user(spotify_user_id).delete_all

      redirect_to spotify_playlists_path
    end
```

private の `fetch_playlists_from_spotify`（461-532 行目）を次に置き換える。

```ruby
    # 原曲名に一致するプレイリストだけを一覧用の Hash に詰め替えて返す。
    #
    # follower 数は GET /me/playlists のレスポンスに含まれないため、以前は
    # RSpotify の method_missing が 1 件ごとに GET /playlists/{id} を暗黙に
    # 発火させていた（実測で 613 件中 612 件が対象 = 一覧表示 1 回あたり
    # 625 リクエスト）。follower の最新化は明示的な「曲数を更新」ボタン
    # (refresh_counts) の責務にして、一覧では DB の既存値を表示する。
    def fetch_playlists_from_spotify
      titles = OriginalSong.playlist_titles.to_set
      code_map = OriginalSong.playlist_code_map

      fetched = SpotifyRetry.with_retry(source: 'Spotify::PlaylistsController#index') do
        SpotifyApi::Playlist.all_mine(spotify_session, limit: LIMIT)
      end

      matched = fetched.select { |playlist| titles.include?(playlist['name']) }
      known_followers = SpotifyPlaylist.where(spotify_id: matched.map { |p| p['id'] })
                                       .pluck(:spotify_id, :followers).to_h

      matched.map do |playlist|
        {
          id: playlist['id'],
          name: playlist['name'],
          external_urls: playlist['external_urls'] || {},
          followers: known_followers.fetch(playlist['id'], 0),
          total: playlist.dig('tracks', 'total').to_i,
          synced_at: nil,
          original_song_code: code_map[playlist['name']]
        }
      end.reverse
    rescue SpotifyApi::RateLimitError => e
      Rails.logger.error("Spotify APIレート制限: #{e.message}")
      @error = 'Spotify APIのレート制限に達しました。しばらく時間をおいて再度お試しください。'
      []
    rescue SpotifyApi::Error => e
      Rails.logger.error("プレイリスト取得エラー: #{e.class} - #{e.message}")
      @error = "プレイリスト情報の取得中にエラーが発生しました: #{e.message}"
      []
    end
```

private の `save_playlists_to_db`（534-546 行目）を次に置き換える。

```ruby
    # find_or_create_by のブロック内で属性を設定していたため、既存レコードが
    # 一切更新されなかった。follower / total を DB 値から表示する設計にした以上、
    # ここが更新されないと画面が古いままになる。
    def save_playlists_to_db(spotify_user_id, playlists)
      playlists.each_with_index do |playlist, index|
        record = SpotifyPlaylist.find_or_initialize_by(spotify_id: playlist[:id])
        record.spotify_user_id = spotify_user_id
        record.name = playlist[:name]
        record.total = playlist[:total]
        record.followers = playlist[:followers]
        record.spotify_url = playlist[:external_urls]['spotify'] || playlist[:external_urls][:spotify]
        record.original_song_code = playlist[:original_song_code]
        record.position = index
        record.save!
      end
    end
```

private の `format_seconds`（447-459 行目）はこの時点ではまだ `fetch_playlists_from_spotify`
以外から参照されていないか確認する。参照が無ければ Task 14 で削除する（今は残す）。

- [ ] **Step 7: テストが通ることを確認する**

Run: `devbox run -- bin/rails test test/controllers/spotify/playlists_controller_test.rb`

Expected: 7 runs, 0 failures。落ちる場合、`sync_single` / `create` / `refresh_counts` /
`original_songs` はまだ RSpotify のままなのでこのテストファイルには含めていない点に注意。

- [ ] **Step 8: RuboCop を通してコミット**

Run: `make rubocop`

```bash
git add app/controllers/concerns/spotify_authentication.rb app/controllers/spotify/playlists_controller.rb config/routes.rb test/controllers/spotify/playlists_controller_test.rb test/fixtures/files/spotify_api/me_playlists.json
git commit -m "index と clear_cache を SpotifyApi へ移行しセッション取得を集約する

- before_action :require_spotify_session に集約し、6箇所のコピペと
  return 漏れによる TypeError を構造的に解消する
- 一覧では follower 数を DB 値から表示し、暗黙の追加リクエストを廃止する
  （実測で 625 リクエスト中 612 リクエストが follower 取得だった）
- save_playlists_to_db が既存レコードを更新しなかったバグを修正する"
```

---

### Task 8: `sync_single` を差し替え、原曲名の再検証を入れる

**目的:** 唯一「外から任意の playlist_id を受け取って破壊的操作に到達しうる経路」を塞ぎ、全消し→全追加を `replace_items` に置き換える。

**Files:**
- Modify: `app/controllers/spotify/playlists_controller.rb`
- Test: `test/controllers/spotify/playlists_controller_test.rb`

**Interfaces:**
- Consumes: `SpotifyApi::Playlist.all_mine`、`SpotifyApi::Playlist.replace_items(session, id, uris)`、`SpotifyApi::Playlist.add_items(session, id, uris)`、`OriginalSong.playlist_title?`
- Produces: `Spotify::PlaylistsController#find_user_playlist(playlist_id, expected_name) -> SpotifyApi::Response | nil`

- [ ] **Step 1: 失敗するテストを書く**

`test/controllers/spotify/playlists_controller_test.rb` のクラス内に追加する。

```ruby
    def create_spotify_track(spotify_id)
      album = Album.create!(name: "テストアルバム #{spotify_id}")
      track = Track.create!(name: "テスト曲 #{spotify_id}", album:)
      TracksOriginalSong.create!(track:, original_song_code: @song.code)
      SpotifyTrack.create!(track:, spotify_id:, name: track.name)
    end

    test 'sync_single replaces playlist items with the original song tracks' do
      log_in
      create_spotify_track('TRACK1')
      stub_spotify_get('me/playlists', body: me_playlists_body,
                       query: { 'limit' => '50', 'offset' => '0' })
      put_stub = stub_spotify_put('playlists/PL_MATCHED/tracks', body: { snapshot_id: 'snap3' })

      post spotify_playlist_sync_path(id: 'PL_MATCHED', name: @song.title)

      assert_redirected_to spotify_playlists_path
      assert_requested put_stub do |req|
        JSON.parse(req.body)['uris'] == ['spotify:track:TRACK1']
      end
    end

    test 'sync_single refuses a playlist whose name is not an original song' do
      log_in
      stub_spotify_get('me/playlists', body: me_playlists_body,
                       query: { 'limit' => '50', 'offset' => '0' })

      post spotify_playlist_sync_path(id: 'PL_UNMATCHED', name: '原曲名ではないプレイリスト')

      assert_redirected_to spotify_playlists_path
      assert_not_requested :put, "#{SpotifyApiStubs::API_BASE}/playlists/PL_UNMATCHED/tracks"
      assert_not_requested :post, "#{SpotifyApiStubs::API_BASE}/playlists/PL_UNMATCHED/tracks"
    end

    test 'sync_single refuses when the id does not belong to the user' do
      log_in
      create_spotify_track('TRACK1')
      stub_spotify_get('me/playlists', body: me_playlists_body,
                       query: { 'limit' => '50', 'offset' => '0' })

      post spotify_playlist_sync_path(id: 'PL_SOMEONE_ELSE', name: @song.title)

      assert_redirected_to spotify_playlists_path
      assert_not_requested :put, "#{SpotifyApiStubs::API_BASE}/playlists/PL_SOMEONE_ELSE/tracks"
    end

    test 'sync_single refuses when the id maps to a different playlist name' do
      log_in
      create_spotify_track('TRACK1')
      stub_spotify_get('me/playlists', body: me_playlists_body,
                       query: { 'limit' => '50', 'offset' => '0' })

      post spotify_playlist_sync_path(id: 'PL_UNMATCHED', name: @song.title)

      assert_redirected_to spotify_playlists_path
      assert_not_requested :put, "#{SpotifyApiStubs::API_BASE}/playlists/PL_UNMATCHED/tracks"
    end
```

`Album` / `Track` / `TracksOriginalSong` / `SpotifyTrack` の必須カラムが上記と異なる場合は、
`devbox run -- bin/rails runner 'puts Album.column_names.inspect'` 等で確認して補うこと。

- [ ] **Step 2: テストが失敗することを確認する**

Run: `devbox run -- bin/rails test test/controllers/spotify/playlists_controller_test.rb -n /sync_single/`

Expected: FAIL。

- [ ] **Step 3: sync_single を差し替える**

`app/controllers/spotify/playlists_controller.rb` の `sync_single`（61-121 行目）を次に置き換える。

```ruby
    def sync_single
      playlist_id = params[:id]
      playlist_name = params[:name]

      # このアプリが書き込んでよいのは原曲名のプレイリストだけ。
      # playlist_id は外部から渡されるため、破壊的操作の前にサーバ側で必ず検証する。
      original_song = OriginalSong.non_duplicated.find_by(title: playlist_name)
      if original_song.nil?
        redirect_to spotify_playlists_path, alert: "原曲が見つかりません: #{playlist_name}"
        return
      end

      # id がユーザー自身のプレイリストであり、かつ実際の名前が原曲名と一致することを確認する。
      playlist = find_user_playlist(playlist_id, playlist_name)
      if playlist.nil?
        redirect_to spotify_playlists_path, alert: "プレイリストが見つかりません: #{playlist_name}"
        return
      end

      # through関連の複雑さを避けるため直接SQL
      spotify_tracks = SpotifyTrack.find_by_sql([<<~SQL.squish, original_song.code])
        SELECT spotify_tracks.*
        FROM spotify_tracks
        INNER JOIN tracks ON tracks.id = spotify_tracks.track_id
        INNER JOIN tracks_original_songs ON tracks_original_songs.track_id = tracks.id
        WHERE tracks_original_songs.original_song_code = ?
      SQL
      if spotify_tracks.empty?
        redirect_to spotify_playlists_path, alert: I18n.t('spotify.playlists.alerts.tracks_not_found')
        return
      end

      replace_playlist_tracks(playlist_id, spotify_tracks)

      spotify_playlist = SpotifyPlaylist.find_by(spotify_id: playlist_id)
      spotify_playlist&.update(total: spotify_tracks.size, synced_at: Time.current)

      redirect_to spotify_playlists_path, notice: "#{playlist_name}を同期しました（#{spotify_tracks.size}曲）"
    rescue StandardError => e
      Rails.logger.error "sync_single error: #{e.class} - #{e.message}"
      redirect_to spotify_playlists_path, alert: "同期エラー: #{e.message}"
    end
```

private の `find_user_playlist`（396-411 行目）を次に置き換える。

```ruby
    # 指定 id がユーザー自身のプレイリストで、かつ名前が期待値と一致する場合だけ返す。
    # 名前の一致まで見るのは、外部から渡された id で別のプレイリストを壊さないため。
    def find_user_playlist(playlist_id, expected_name)
      playlists = SpotifyRetry.with_retry(source: 'Spotify::PlaylistsController#sync_single') do
        SpotifyApi::Playlist.all_mine(spotify_session, limit: LIMIT)
      end

      playlists.find { |p| p['id'] == playlist_id && p['name'] == expected_name }
    end
```

private セクションの先頭付近に、書き込み処理を追加する。

```ruby
    # 全消し → 全追加を PUT 1 回（+ 100 件超の分だけ POST）に置き換える。
    # PUT /playlists/{id}/tracks は uris で中身を丸ごと差し替えるため、
    # 先頭 100 件を PUT した後に残りを 100 件ずつ POST で足す。順序が入れ替わると
    # 先に足した分が消えるので、PUT を必ず先に実行すること。
    def replace_playlist_tracks(playlist_id, spotify_tracks)
      uris = spotify_tracks.map { |track| "spotify:track:#{track.spotify_id}" }

      SpotifyRetry.with_retry(source: 'Spotify::PlaylistsController#sync_single') do
        SpotifyApi::Playlist.replace_items(spotify_session, playlist_id, uris.first(100))
      end

      uris.drop(100).each_slice(100) do |batch|
        SpotifyRetry.with_retry(source: 'Spotify::PlaylistsController#sync_single') do
          SpotifyApi::Playlist.add_items(spotify_session, playlist_id, batch)
        end
      end
    end
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `devbox run -- bin/rails test test/controllers/spotify/playlists_controller_test.rb`

Expected: 全 test pass。

- [ ] **Step 5: RuboCop を通してコミット**

Run: `make rubocop`

```bash
git add app/controllers/spotify/playlists_controller.rb test/controllers/spotify/playlists_controller_test.rb
git commit -m "sync_single を SpotifyApi へ移行し原曲名をサーバ側で再検証する

- playlist_id は外部から渡されるため、破壊的操作の前に
  「原曲名に一致する」「ユーザー自身のプレイリストである」
  「実際の名前が指定名と一致する」の3点を検証する
- 全消し→全追加のループを replace_items 1回 + 100件ずつの add_items に置き換える
- RSpotify::Track.find を廃止し URI を文字列組み立てにする"
```

---

### Task 9: `refresh_counts` を差し替える

**目的:** 96 行のインライン実装から RSpotify を外し、follower 取得を明示的なループにして `SpotifyRetry` を効かせる。

**Files:**
- Modify: `app/controllers/spotify/playlists_controller.rb`
- Create: `test/fixtures/files/spotify_api/playlist_detail.json`
- Test: `test/controllers/spotify/playlists_controller_test.rb`

**Interfaces:**
- Consumes: `SpotifyApi::Playlist.all_mine`、`SpotifyApi::Playlist.find(session, id)`、`OriginalSong.playlist_titles`、`OriginalSong.playlist_code_map`

- [ ] **Step 1: fixture を作成する**

`test/fixtures/files/spotify_api/playlist_detail.json` を Write ツールで作成する。

```json
{
  "collaborative": false,
  "description": "",
  "external_urls": { "spotify": "https://open.spotify.com/playlist/PL_MATCHED" },
  "followers": { "href": null, "total": 42 },
  "href": "https://api.spotify.com/v1/playlists/PL_MATCHED",
  "id": "PL_MATCHED",
  "images": [],
  "name": "PLAYLIST_TITLE_MATCHED",
  "owner": { "id": "test-user", "type": "user" },
  "primary_color": null,
  "public": true,
  "snapshot_id": "snap1",
  "tracks": { "href": "https://api.spotify.com/v1/playlists/PL_MATCHED/tracks", "total": 7 },
  "type": "playlist",
  "uri": "spotify:playlist:PL_MATCHED"
}
```

- [ ] **Step 2: 失敗するテストを書く**

`test/controllers/spotify/playlists_controller_test.rb` のクラス内に追加する。
`refresh_counts` は `Thread.new` で非同期実行されるため、テストではスレッドの完了を待つ。

```ruby
    def playlist_detail_body
      spotify_fixture('playlist_detail').gsub('PLAYLIST_TITLE_MATCHED', @song.title)
    end

    def wait_for_refresh_counts(timeout: 5)
      deadline = Time.current + timeout
      loop do
        raw = RedisPool.with { |r| r.get("refresh_counts:#{@user.id}") }
        info = raw.present? ? JSON.parse(raw) : {}
        return info if %w[completed error].include?(info['status'])
        raise "refresh_counts did not finish: #{info.inspect}" if Time.current > deadline

        sleep 0.05
      end
    end

    test 'refresh_counts updates follower counts for original-song playlists only' do
      log_in
      stub_spotify_get('me/playlists', body: me_playlists_body,
                       query: { 'limit' => '50', 'offset' => '0' })
      detail_stub = stub_spotify_get('playlists/PL_MATCHED', body: playlist_detail_body)

      post spotify_playlists_refresh_counts_path

      info = wait_for_refresh_counts
      assert_equal 'completed', info['status']
      assert_requested detail_stub
      assert_not_requested :get, "#{SpotifyApiStubs::API_BASE}/playlists/PL_UNMATCHED"

      record = SpotifyPlaylist.find_by(spotify_id: 'PL_MATCHED')
      assert_equal 42, record.followers
      assert_equal 7, record.total
      assert_equal @song.code, record.original_song_code
      assert_nil SpotifyPlaylist.find_by(spotify_id: 'PL_UNMATCHED')
    end

    test 'refresh_counts redirects to root when not logged in' do
      post spotify_playlists_refresh_counts_path

      assert_redirected_to root_url
    end
```

- [ ] **Step 3: テストが失敗することを確認する**

Run: `devbox run -- bin/rails test test/controllers/spotify/playlists_controller_test.rb -n /refresh_counts/`

Expected: FAIL。

- [ ] **Step 4: refresh_counts を差し替える**

`app/controllers/spotify/playlists_controller.rb` の `refresh_counts`（191-295 行目）を次に置き換える。

```ruby
    def refresh_counts
      progress_key = "refresh_counts:#{session[:user_id]}"
      redis = RedisPool.get
      redis.set(progress_key, {
        total: 0, current: 0, current_playlist: '',
        status: 'processing', started_at: Time.current.to_s, completed_at: nil
      }.to_json)

      spotify_user_id = self.spotify_user_id
      spotify_session = self.spotify_session
      Thread.new do
        refresh_counts_in_background(spotify_session, spotify_user_id, progress_key)
      ensure
        ActiveRecord::Base.connection_pool.release_connection
      end

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace('refresh-counts-container',
                                                    partial: 'refresh_counts_progress')
        end
        format.html { redirect_to spotify_playlists_path }
      end
    end
```

private セクションに実処理を追加する。

```ruby
    # 原曲名に一致するプレイリストの total / followers / position を最新化する。
    #
    # follower 数は GET /me/playlists のレスポンスに含まれないため、1 件ごとに
    # GET /playlists/{id} が必要になる。一覧表示のたびに暗黙で払っていたこの
    # コストを、ユーザーが明示的にボタンを押したときだけ払う形にした。
    def refresh_counts_in_background(spotify_session, spotify_user_id, progress_key)
      redis = RedisPool.get
      titles = OriginalSong.playlist_titles.to_set
      code_map = OriginalSong.playlist_code_map

      playlists = SpotifyRetry.with_retry(source: 'Spotify::PlaylistsController#refresh_counts') do
        SpotifyApi::Playlist.all_mine(spotify_session, limit: LIMIT)
      end
      matched = playlists.select { |p| titles.include?(p['name']) }

      write_refresh_progress(redis, progress_key) { |info| info['total'] = matched.size }

      matched.each_with_index do |playlist, index|
        write_refresh_progress(redis, progress_key) do |info|
          info['current'] = index + 1
          info['current_playlist'] = playlist['name']
        end

        detail = SpotifyRetry.with_retry(source: 'Spotify::PlaylistsController#refresh_counts') do
          SpotifyApi::Playlist.find(spotify_session, playlist['id'])
        end

        record = SpotifyPlaylist.find_or_initialize_by(spotify_id: playlist['id'])
        record.spotify_user_id = spotify_user_id
        record.name = playlist['name']
        record.total = detail.dig('tracks', 'total').to_i
        record.followers = detail.dig('followers', 'total').to_i
        record.spotify_url = playlist.dig('external_urls', 'spotify')
        record.original_song_code = code_map[playlist['name']]
        record.position = index
        record.save!
      end

      write_refresh_progress(redis, progress_key) do |info|
        info['status'] = 'completed'
        info['completed_at'] = Time.current.to_s
      end
    rescue StandardError => e
      Rails.logger.error("refresh_counts error: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      write_refresh_progress(redis, progress_key) do |info|
        info['status'] = 'error'
        info['error_message'] = e.message
      end
    end

    def write_refresh_progress(redis, progress_key)
      raw = redis.get(progress_key)
      info = raw.present? ? JSON.parse(raw) : {}
      yield(info)
      redis.set(progress_key, info.to_json)
    end
```

**注意:** 元の実装にあった `sleep 0.2` は削除する。`SpotifyRetry` が 429 を Retry-After に
従って処理するため、固定 sleep でレート制限を予防する必要が無くなった。

- [ ] **Step 5: テストが通ることを確認する**

Run: `devbox run -- bin/rails test test/controllers/spotify/playlists_controller_test.rb`

Expected: 全 test pass。

- [ ] **Step 6: RuboCop を通してコミット**

Run: `make rubocop`

```bash
git add app/controllers/spotify/playlists_controller.rb test/controllers/spotify/playlists_controller_test.rb test/fixtures/files/spotify_api/playlist_detail.json
git commit -m "refresh_counts を SpotifyApi へ移行する

- follower 取得を GET /playlists/{id} の明示ループにし SpotifyRetry で包む
- 独自のリトライ実装（Retry-After 未参照）と固定 sleep 0.2 を撤去する
- 原曲名に一致するプレイリストだけを取得・保存対象にする"
```

---

### Task 10: `original_songs` を差し替える

**目的:** 最後に残った RSpotify 呼び出しをコントローラから外す。

**Files:**
- Modify: `app/controllers/spotify/playlists_controller.rb`
- Test: `test/controllers/spotify/playlists_controller_test.rb`

- [ ] **Step 1: 失敗するテストを書く**

`test/controllers/spotify/playlists_controller_test.rb` のクラス内に追加する。

```ruby
    test 'original_songs exports playlist urls for matched original songs' do
      log_in
      stub_spotify_get('me/playlists', body: me_playlists_body,
                       query: { 'limit' => '50', 'offset' => '0' })

      get spotify_playlists_original_songs_path

      assert_response :success
      data = JSON.parse(response.body)
      songs = data.values.flatten.flat_map { |o| o['original_songs'] }
      assert_includes songs.map { |s| s['name'] }, @song.title
      assert_includes songs.map { |s| s['playlist_url'] },
                      'https://open.spotify.com/playlist/PL_MATCHED'
      assert_not_includes songs.map { |s| s['name'] }, '原曲名ではないプレイリスト'
    end

    test 'original_songs redirects to root when not logged in' do
      get spotify_playlists_original_songs_path

      assert_redirected_to root_url
    end
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `devbox run -- bin/rails test test/controllers/spotify/playlists_controller_test.rb -n /original_songs/`

Expected: FAIL。

- [ ] **Step 3: original_songs のプレイリスト取得部分を差し替える**

`app/controllers/spotify/playlists_controller.rb` の `original_songs` の冒頭
（306-330 行目、`return redirect_to root_url ...` から `end`（リトライループの終わり）まで）を
次に置き換える。

```ruby
    def original_songs
      @playlists = SpotifyRetry.with_retry(source: 'Spotify::PlaylistsController#original_songs') do
        SpotifyApi::Playlist.all_mine(spotify_session, limit: LIMIT)
      end
```

同メソッド内の 348-349 行目:

```ruby
            playlist = @playlists.find { |p| p.name == song.title }
            playlist_url = playlist&.external_urls&.dig('spotify')
```

を次に置き換える。

```ruby
            playlist = @playlists.find { |p| p['name'] == song.title }
            playlist_url = playlist&.dig('external_urls', 'spotify')
```

`before_action` が未ログインを処理するため、メソッド冒頭の
`return redirect_to root_url unless session[:user_id]` と Redis からの auth_hash 読み出し
（308-310 行目）は削除する。

- [ ] **Step 4: テストが通ることを確認する**

Run: `devbox run -- bin/rails test test/controllers/spotify/playlists_controller_test.rb`

Expected: 全 test pass。

- [ ] **Step 5: コントローラから RSpotify の参照が消えたことを確認する**

Run: `grep -n 'RSpotify' app/controllers/spotify/playlists_controller.rb`

Expected: 出力なし（exit 1）。

- [ ] **Step 6: RuboCop を通してコミット**

Run: `make rubocop`

```bash
git add app/controllers/spotify/playlists_controller.rb test/controllers/spotify/playlists_controller_test.rb
git commit -m "original_songs を SpotifyApi へ移行する

- 独自のリトライループを SpotifyRetry.with_retry に置き換える
- これで playlists_controller から RSpotify の参照が消えた"
```

---

### Task 11: `PlaylistUpdateService` を差し替える

**目的:** サービス層から RSpotify を外し、「retry via caller」と書きつつ実際には再試行されずサービス全体を停止させていたエラーハンドリングを撤去する。

**Files:**
- Modify: `app/services/spotify/playlist_update_service.rb`
- Modify: `app/controllers/spotify/playlists_controller.rb`（`create` アクション）
- Test: `test/services/spotify/playlist_update_service_test.rb`（新規）

**Interfaces:**
- Consumes: `SpotifyApi::Playlist.all_mine`、`.create(session, name:)`、`.replace_items`、`.add_items`
- Produces: `Spotify::PlaylistUpdateService.call(update_type:, spotify_session:, user_id:) -> void`
  （**`spotify_user:` から `spotify_session:` にキーワードが変わる**）

- [ ] **Step 1: 失敗するテストを書く**

`test/services/spotify/playlist_update_service_test.rb` を Write ツールで作成する。

```ruby
# frozen_string_literal: true

require 'test_helper'

module Spotify
  class PlaylistUpdateServiceTest < ActiveSupport::TestCase
    parallelize(workers: 1)

    setup do
      @original = Original.create!(code: 'TEST_ORIG_SVC', title: 'テスト作品', original_type: :windows,
                                   series_order: 9980)
      @song = OriginalSong.create!(code: 'TEST_SONG_SVC', original_code: @original.code,
                                   title: 'サービステスト原曲', track_number: 1, is_duplicate: false)
      album = Album.create!(name: 'サービステストアルバム')
      track = Track.create!(name: 'サービステスト曲', album:)
      TracksOriginalSong.create!(track:, original_song_code: @song.code)
      SpotifyTrack.create!(track:, spotify_id: 'SVCTRACK1', name: track.name)

      @user_id = SecureRandom.uuid
      @session = SpotifyApi::UserSession.new(
        { 'uid' => 'test-user',
          'credentials' => { 'token' => 'USER_TOKEN', 'refresh_token' => 'REFRESH_TOKEN',
                             'expires_at' => 1.hour.from_now.to_i } }
      )
      RedisPool.with { |r| r.set("playlist_update:#{@user_id}", { 'status' => 'processing' }.to_json) }
    end

    teardown do
      RedisPool.with { |r| r.del("playlist_update:#{@user_id}") }
    end

    def empty_playlists_body
      { 'items' => [], 'total' => 0, 'limit' => 50, 'offset' => 0, 'next' => nil }
    end

    def existing_playlists_body
      { 'items' => [{ 'id' => 'PL_EXISTING', 'name' => @song.title,
                      'external_urls' => { 'spotify' => 'https://open.spotify.com/playlist/PL_EXISTING' },
                      'tracks' => { 'total' => 0 } }],
        'total' => 1, 'limit' => 50, 'offset' => 0, 'next' => nil }
    end

    def progress
      JSON.parse(RedisPool.with { |r| r.get("playlist_update:#{@user_id}") })
    end

    test 'creates a playlist when none exists and replaces its items' do
      stub_spotify_get('me/playlists', body: empty_playlists_body,
                       query: { 'limit' => '50', 'offset' => '0' })
      create_stub = stub_spotify_post('me/playlists', body: { 'id' => 'PL_NEW', 'name' => @song.title })
      put_stub = stub_spotify_put('playlists/PL_NEW/tracks', body: { 'snapshot_id' => 'snap' })

      PlaylistUpdateService.call(update_type: 'windows', spotify_session: @session, user_id: @user_id)

      assert_requested create_stub do |req|
        JSON.parse(req.body)['name'] == @song.title
      end
      assert_requested put_stub do |req|
        JSON.parse(req.body)['uris'] == ['spotify:track:SVCTRACK1']
      end
      assert_equal 'completed', progress['status']
    end

    test 'reuses an existing playlist instead of creating a duplicate' do
      stub_spotify_get('me/playlists', body: existing_playlists_body,
                       query: { 'limit' => '50', 'offset' => '0' })
      put_stub = stub_spotify_put('playlists/PL_EXISTING/tracks', body: { 'snapshot_id' => 'snap' })

      PlaylistUpdateService.call(update_type: 'windows', spotify_session: @session, user_id: @user_id)

      assert_requested put_stub
      assert_not_requested :post, "#{SpotifyApiStubs::API_BASE}/me/playlists"
    end

    test 'marks progress as error and re-raises on failure' do
      stub_spotify_get('me/playlists', body: empty_playlists_body,
                       query: { 'limit' => '50', 'offset' => '0' })
      stub_spotify_post('me/playlists', body: { 'error' => 'boom' }, status: 500)

      assert_raises(SpotifyApi::ServerError) do
        PlaylistUpdateService.call(update_type: 'windows', spotify_session: @session,
                                   user_id: @user_id)
      end

      assert_equal 'error', progress['status']
    end
  end
end
```

`marks progress as error` のテストは `SpotifyRetry` が 500 を指数バックオフで 5 回再試行する
ため時間がかかる。`SpotifyRetry.with_retry` に `sleeper:` を渡せる設計になっているので、
サービス側にテスト用の注入口が無い場合は、このテストを
`stub_spotify_post('me/playlists', body: {}, status: 403)`（`ForbiddenError` は
`TRANSIENT_ERRORS` に含まれないため即座に伝播する）に変更して `SpotifyApi::ForbiddenError`
を期待すること。

- [ ] **Step 2: テストが失敗することを確認する**

Run: `devbox run -- bin/rails test test/services/spotify/playlist_update_service_test.rb`

Expected: FAIL（`unknown keyword: :spotify_session`）。

- [ ] **Step 3: サービスを差し替える**

`app/services/spotify/playlist_update_service.rb` を編集する。

定数（9-12 行目）から `MAX_RETRIES` を削除する（`SpotifyRetry` に統合するため）。
`LIMIT = 50` と `PROGRESS_UPDATE_INTERVAL = 5` は残す。

`initialize`（20-28 行目）:

```ruby
    def initialize(update_type:, spotify_session:, user_id:)
      @update_type = update_type
      @spotify_session = spotify_session
      @user_id = user_id
      @redis = RedisPool.get
      @progress_key = "playlist_update:#{user_id}"
      @playlists_cache = nil
      @progress_info = load_progress_info
    end
```

`attr_reader`（49 行目）の `spotify_user` を `spotify_session` に変更する。

```ruby
    attr_reader :update_type, :spotify_session, :user_id, :redis, :progress_key, :progress_info
```

`process_original_song`（100-122 行目）の rescue 節を差し替える。
`OpenSSL::SSL::SSLError` と `RestClient::TooManyRequests` の rescue を削除し、
`StandardError` のログのみ残す（リトライは `SpotifyRetry` が担う）。

```ruby
    def process_original_song(original_song, current_count)
      spotify_tracks = original_song.spotify_tracks
      return current_count if spotify_tracks.empty?

      update_progress(
        current_song: original_song.title,
        current: current_count,
        arrangement_count: spotify_tracks.size
      )

      update_playlist_for_song(original_song, spotify_tracks)

      current_count + 1
    rescue SpotifyApi::QuotaExceededError
      # クォータ超過は待っても回復しないため、握りつぶさず処理全体を止める。
      raise
    rescue StandardError => e
      Rails.logger.error("Error processing song #{original_song.title}: #{e.class} - #{e.message}")
      current_count + 1
    end
```

`update_playlist_for_song`（124-130 行目）:

```ruby
    def update_playlist_for_song(original_song, spotify_tracks)
      playlist = find_or_create_playlist(original_song.title)
      return unless playlist

      replace_playlist_tracks(playlist['id'], spotify_tracks)
    end
```

`find_or_create_playlist`（132-141 行目）:

```ruby
    # 作成直後に RSpotify::Playlist.find_by_id で取り直していたが、
    # POST /me/playlists のレスポンスがそのまま使えるため 1 往復を削る。
    def find_or_create_playlist(title)
      playlist = find_playlist(title)
      return playlist if playlist

      SpotifyRetry.with_retry(source: 'Spotify::PlaylistUpdateService#create_playlist') do
        SpotifyApi::Playlist.create(spotify_session, name: title)
      end
    end
```

`find_playlist`（143-153 行目）:

```ruby
    def find_playlist(playlist_name)
      load_playlists_cache if @playlists_cache.nil?

      @playlists_cache.find { |playlist| playlist['name'] == playlist_name }
    end
```

`load_playlists_cache`（155-168 行目）と `rate_limit_retry_allowed?`（170-191 行目）を
次の 1 メソッドに置き換える。

```ruby
    def load_playlists_cache
      @playlists_cache = SpotifyRetry.with_retry(source: 'Spotify::PlaylistUpdateService#load_playlists') do
        SpotifyApi::Playlist.all_mine(spotify_session, limit: LIMIT)
      end
    end
```

`clear_playlist_tracks`（193-200 行目）と `add_tracks_to_playlist`（202-209 行目）を
次の 1 メソッドに置き換える。

```ruby
    # 全消し（tracks を取得して remove を繰り返す）→ 全追加のループを
    # PUT 1 回（+ 100 件超の分だけ POST）に置き換える。
    # PUT は中身を丸ごと差し替えるため、必ず PUT を先に実行すること。
    def replace_playlist_tracks(playlist_id, spotify_tracks)
      uris = spotify_tracks.map { |track| "spotify:track:#{track.spotify_id}" }

      SpotifyRetry.with_retry(source: 'Spotify::PlaylistUpdateService#replace_items') do
        SpotifyApi::Playlist.replace_items(spotify_session, playlist_id, uris.first(100))
      end

      uris.drop(100).each_slice(100) do |batch|
        SpotifyRetry.with_retry(source: 'Spotify::PlaylistUpdateService#add_items') do
          SpotifyApi::Playlist.add_items(spotify_session, playlist_id, batch)
        end
      end
    end
```

`handle_ssl_error`（211-223 行目）、`handle_rate_limit_error`（225-248 行目）、
`format_seconds`（282-294 行目）を削除する。3 つとも上記の変更で参照されなくなる。

- [ ] **Step 4: コントローラの `create` を合わせる**

`app/controllers/spotify/playlists_controller.rb` の `create`（123-177 行目）を次に置き換える。

```ruby
    def create
      update_type = params[:update_type]

      if update_type.blank?
        redirect_to spotify_playlists_path
        return
      end

      progress_key = "playlist_update:#{session[:user_id]}"
      redis = RedisPool.get
      redis.set(progress_key, {
        update_type:, total: 0, current: 0, current_song: '', current_original: '',
        songs_in_original: 0, arrangement_count: 0, status: 'processing',
        started_at: Time.current.to_s, completed_at: nil
      }.to_json)

      user_id = session[:user_id]
      spotify_session = self.spotify_session
      Thread.new do
        PlaylistUpdateService.call(update_type:, spotify_session:, user_id:)
      rescue StandardError => e
        Rails.logger.error("プレイリスト更新エラー: #{e.class} - #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
      ensure
        ActiveRecord::Base.connection_pool.release_connection
      end

      redirect_to spotify_playlists_progress_path
    end
```

`mark_error` はサービス側が既に Redis へ書くため、コントローラ側の rescue では
ログのみ残す（従来は二重に書いていた）。

- [ ] **Step 5: テストが通ることを確認する**

Run: `devbox run -- bin/rails test test/services/spotify/playlist_update_service_test.rb test/controllers/spotify/playlists_controller_test.rb`

Expected: 全 test pass。

- [ ] **Step 6: app/ から RSpotify の参照が消えたことを確認する**

Run: `grep -rn 'RSpotify' app/controllers/ app/services/`

Expected: 出力なし（exit 1）。

- [ ] **Step 7: 全テストと RuboCop を通してコミット**

Run: `make minitest && make rubocop`

```bash
git add app/services/spotify/playlist_update_service.rb app/controllers/spotify/playlists_controller.rb test/services/spotify/playlist_update_service_test.rb
git commit -m "PlaylistUpdateService を SpotifyApi へ移行する

- spotify_user: キーワードを spotify_session: に変更する
- 作成直後の再取得を廃止し POST /me/playlists のレスポンスをそのまま使う
- 全消し→全追加のループを replace_items 1回 + 100件ずつの add_items に置き換える
- handle_ssl_error / handle_rate_limit_error を削除する。「retry via caller」と
  書かれていたが呼び出し元に retry 機構が無く、実際には再試行されないまま
  サービス全体を停止させていた
- これで app/controllers と app/services から RSpotify の参照が消えた"
```

---

### Task 12: Redis キーに prefix と TTL を付ける

**目的:** auth_hash が `user.id` の生値で進捗キーと同一名前空間に混在し、無期限に平文の refresh_token を保持している状態を解消する。

**Files:**
- Modify: `lib/spotify_api/user_session.rb`
- Modify: `app/controllers/sessions_controller.rb`
- Test: `test/lib/spotify_api/user_session_test.rb`
- Test: `test/controllers/sessions_controller_test.rb`

**Interfaces:**
- Produces: `SpotifyApi::UserSession.redis_key(user_id) -> String`（`"spotify:auth:#{user_id}"`）
- Produces: `SpotifyApi::UserSession::TTL`（`90.days`）

**前提:** Task 7〜11 で auth_hash を読むのは `SpotifyApi::UserSession.find` だけになっている。
このタスクで書き手（`sessions_controller`）と読み手（`UserSession`）を同時に変える。
**既存の Redis 上の auth_hash は旧キーのまま残るため、この変更後は 1 回の再ログインが必要になる。**
Task 5 の scope 変更でどのみち再認可が必要なので、ここでまとめて済ませる。

- [ ] **Step 1: 失敗するテストを書く**

`test/lib/spotify_api/user_session_test.rb` のクラス内に追加する。

```ruby
    test 'redis_key namespaces the auth hash' do
      assert_equal 'spotify:auth:abc-123', SpotifyApi::UserSession.redis_key('abc-123')
    end

    test 'find reads from the namespaced key' do
      user_id = SecureRandom.uuid
      hash = { 'uid' => 'test-user',
               'credentials' => { 'token' => 'T', 'refresh_token' => 'R',
                                  'expires_at' => 1.hour.from_now.to_i } }
      RedisPool.with { |r| r.set(SpotifyApi::UserSession.redis_key(user_id), hash.to_json) }

      session = SpotifyApi::UserSession.find(user_id)

      assert_not_nil session
      assert_equal 'test-user', session.spotify_user_id
    ensure
      RedisPool.with { |r| r.del(SpotifyApi::UserSession.redis_key(user_id)) }
    end
```

`test/controllers/sessions_controller_test.rb` を以下の内容で書き換える。

```ruby
# frozen_string_literal: true

require 'test_helper'

class SessionsControllerTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  setup do
    OmniAuth.config.test_mode = true
    @auth = OmniAuth::AuthHash.new(
      provider: 'spotify',
      uid: 'test-user',
      info: { id: 'test-user', display_name: 'Test User', email: 'test@example.com',
              images: [{ 'url' => 'https://example.test/avatar.png' }] },
      credentials: { token: 'USER_TOKEN', refresh_token: 'REFRESH_TOKEN',
                     expires_at: 1.hour.from_now.to_i, expires: true }
    )
    OmniAuth.config.mock_auth[:spotify] = @auth
  end

  teardown do
    OmniAuth.config.test_mode = false
    User.where(provider: 'spotify', uid: 'test-user').each do |u|
      RedisPool.with { |r| r.del(SpotifyApi::UserSession.redis_key(u.id)) }
    end
  end

  test 'callback creates a user and stores the auth hash under a namespaced key with a TTL' do
    get '/auth/spotify/callback', env: { 'omniauth.auth' => @auth }

    assert_redirected_to root_path
    user = User.find_by!(provider: 'spotify', uid: 'test-user')

    key = SpotifyApi::UserSession.redis_key(user.id)
    stored = RedisPool.with { |r| r.get(key) }
    assert_not_nil stored
    assert_equal 'REFRESH_TOKEN', JSON.parse(stored).dig('credentials', 'refresh_token')

    ttl = RedisPool.with { |r| r.ttl(key) }
    assert_operator ttl, :>, 0
    assert_operator ttl, :<=, SpotifyApi::UserSession::TTL.to_i
  end

  test 'logout deletes the namespaced auth hash' do
    get '/auth/spotify/callback', env: { 'omniauth.auth' => @auth }
    user = User.find_by!(provider: 'spotify', uid: 'test-user')

    delete '/logout'

    assert_redirected_to root_path
    assert_nil RedisPool.with { |r| r.get(SpotifyApi::UserSession.redis_key(user.id)) }
  end
end
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `devbox run -- bin/rails test test/lib/spotify_api/user_session_test.rb test/controllers/sessions_controller_test.rb`

Expected: FAIL（`NoMethodError: undefined method 'redis_key'`）。

- [ ] **Step 3: UserSession にキーと TTL を実装する**

`lib/spotify_api/user_session.rb` を編集する。

`REFRESH_MARGIN` の下に定数を追加する。

```ruby
    REFRESH_MARGIN = 60.seconds # 期限切れ前に再取得を始めるマージン（SpotifyApi::Config と同じ考え方）

    # auth_hash の Redis キーの接頭辞。以前は user.id の生値をキーにしていたため、
    # playlist_update:* / refresh_counts:* と同じ名前空間に混在していた。
    KEY_PREFIX = 'spotify:auth:'

    # refresh_token は revoke されるまで失効しないため、無期限に平文で保持しない。
    # TTL 経過後はログインし直してもらう。
    TTL = 90.days
```

`class << self` 内に `redis_key` を追加し、`find` を書き換える。

```ruby
    class << self
      def redis_key(user_id)
        "#{KEY_PREFIX}#{user_id}"
      end

      # Redis から auth_hash を読み込んで UserSession を組み立てる。該当キーが無ければ nil を返す。
      #
      # rspotify の RSpotify::User は該当ユーザーの認証情報が見つからないと
      # 「最初に登録されたユーザーのトークン」にフォールバックする（rspotify/user.rb:66）。
      # マルチユーザー環境では別人のアカウントにプレイリストを書き込む事故につながるため、
      # SpotifyApi ではこの挙動を絶対に引き継がない。見つからなければ黙って nil を返すだけにする。
      def find(user_id, config: SpotifyApi.config)
        json = RedisPool.with { |redis| redis.get(redis_key(user_id)) }
        return nil if json.blank?

        new(JSON.parse(json), user_id:, config:)
      end
    end
```

`persist!`（118-124 行目）を書き換える。TTL を維持したまま書き戻す。

```ruby
    def persist!
      return if user_id.blank?

      RedisPool.with do |redis|
        redis.set(self.class.redis_key(user_id), auth_hash.to_json, ex: TTL.to_i)
      end
    rescue StandardError => e
      Rails.logger.warn("SpotifyApi::UserSession#persist!: failed to write back to Redis (#{e.class}: #{e.message})")
    end
```

クラス冒頭のコメント（10-13 行目）も実態に合わせて更新する。

```ruby
    # app/controllers/sessions_controller.rb が OmniAuth の auth_hash を
    # SpotifyApi::UserSession.redis_key(user.id) をキーに保存しているため、
    # find はその値を読み込んで UserSession を組み立てる。auth_hash は JSON 経由
    # なのでキーは文字列である点に注意（credentials['token'] のようにアクセスする）。
```

- [ ] **Step 4: SessionsController を合わせる**

`app/controllers/sessions_controller.rb` を以下の内容に書き換える。

```ruby
# frozen_string_literal: true

class SessionsController < ApplicationController
  # ログアウト処理ではCSRF検証をスキップ（セキュリティ上問題ない）
  skip_before_action :verify_authenticity_token, only: [:destroy]

  def create
    user = User.find_or_create_from_auth_hash(auth_hash)
    RedisPool.with do |redis|
      redis.set(SpotifyApi::UserSession.redis_key(user.id), auth_hash.to_json,
                ex: SpotifyApi::UserSession::TTL.to_i)
    end

    session[:user_id] = user.id
    redirect_to root_path
  end

  def destroy
    if session[:user_id]
      RedisPool.with { |redis| redis.del(SpotifyApi::UserSession.redis_key(session[:user_id])) }
    end
    reset_session
    redirect_to root_path
  end

  protected

  def auth_hash
    request.env['omniauth.auth']
  end
end
```

- [ ] **Step 5: コントローラテストのキーを合わせる**

`test/controllers/spotify/playlists_controller_test.rb` の `store_auth_hash` と `teardown` で
`r.set(@user.id, ...)` / `r.del(@user.id, ...)` を使っている箇所を
`SpotifyApi::UserSession.redis_key(@user.id)` に変更する。

- [ ] **Step 6: 全テストが通ることを確認する**

Run: `make minitest`

Expected: 全 test pass。

- [ ] **Step 7: RuboCop を通してコミット**

Run: `make rubocop`

```bash
git add lib/spotify_api/user_session.rb app/controllers/sessions_controller.rb test/lib/spotify_api/user_session_test.rb test/controllers/sessions_controller_test.rb test/controllers/spotify/playlists_controller_test.rb
git commit -m "auth_hash の Redis キーに prefix と TTL を付ける

- キーを user.id の生値から spotify:auth:<user_id> に変更する
  （進捗キー playlist_update:* / refresh_counts:* と同じ名前空間に混在していた）
- TTL 90日を設定する。refresh_token は revoke されるまで失効しないため、
  無期限に平文で保持しない
- リフレッシュ後の書き戻しでも TTL を維持する"
```

**注意:** この変更後、既存の Redis 上の auth_hash（旧キー）は読まれなくなる。動作確認の前に
一度ログインし直すこと。旧キーは Task 15 で削除する。

---

### Task 13: routes と view の実バグを修正する

**目的:** GET で副作用アクションが起動できる状態と、Turbo 下で機能していないボタンを直す。

**Files:**
- Modify: `config/routes.rb:44`
- Modify: `app/views/spotify/playlists/index.html.erb:15`

**確認済み:** `playlists#create` の呼び出し元は `app/views/root/index.html.erb` の 5 箇所で、
すべて `data: { turbo_method: :post }` を使っている。POST 限定にしても壊れない。

- [ ] **Step 1: routes を POST 限定にする**

`config/routes.rb:44`:

```ruby
    match 'playlists/create', to: 'playlists#create', via: %i[get post]
```

を次に置き換える。

```ruby
    post 'playlists/create', to: 'playlists#create'
```

- [ ] **Step 2: view の delete リンクを修正する**

`app/views/spotify/playlists/index.html.erb:15`:

```erb
      <%= link_to '最新情報を取得', spotify_clear_playlists_cache_path, method: :delete, class: 'btn btn-small btn-outline' %>
```

を次に置き換える。`link_to ... method: :delete` は Rails 7 以降の Turbo では効かず、
GET リクエストになってルーティングエラーになっていた。

```erb
      <%= link_to '最新情報を取得', spotify_clear_playlists_cache_path, data: { turbo_method: :delete }, class: 'btn btn-small btn-outline' %>
```

- [ ] **Step 3: ルーティングを確認する**

Run: `devbox run -- bin/rails routes -g playlists`

Expected: `spotify_playlists_create POST /spotify/playlists/create` と表示され、GET が消えている。

- [ ] **Step 4: 全テストと RuboCop を通してコミット**

Run: `make minitest && make rubocop`

```bash
git add config/routes.rb app/views/spotify/playlists/index.html.erb
git commit -m "GET で副作用アクションが起動できる状態と効かないボタンを修正する

- playlists/create を POST 限定にする（呼び出し元は全て turbo_method: :post）
- 「最新情報を取得」の link_to method: :delete は Turbo では効かず GET に
  なっていたため data: { turbo_method: :delete } に修正する"
```

---

### Task 14: デッドコードを撤去する

**目的:** 参照されていないコードと、それ専用の依存を消す。

**Files:**
- Delete: `app/services/spotify_web_api/client.rb`
- Delete: `test/services/spotify_web_api_client_test.rb`
- Delete: `app/views/spotify/playlists/create.html.erb`
- Modify: `Gemfile`（`spotify-client` を削除）
- Modify: `app/models/spotify_playlist.rb`（`scope :stale` を削除）
- Modify: `app/controllers/spotify/playlists_controller.rb`（残った未使用 private メソッド）

**`rspotify` gem は残す。** `app/models/spotify_client/{album,track,audio_features}/rspotify_backend.rb`
と `spotify_retry.rb` / `spotify_rate_limit.rb` の `RestClient::*` 参照が Issue #563 まで生きている。

- [ ] **Step 1: 参照が無いことを確認する**

Run: `grep -rn 'SpotifyWebApi\|spotify/client\|Spotify::Client' app/ lib/ config/ test/ | grep -v 'app/services/spotify_web_api/client.rb\|test/services/spotify_web_api_client_test.rb'`

Expected: 出力なし。何か出た場合は削除せず報告する。

Run: `grep -rn '\.stale\b' app/ lib/ test/`

Expected: 出力なし。

Run: `grep -rn 'format_seconds\|CACHE_TTL\|MAX_RETRIES' app/controllers/spotify/playlists_controller.rb`

Expected: `format_seconds` の定義のみ（`load_progress_info` / `load_refresh_counts_info` は
`@processing_time` を秒で持つだけで `format_seconds` を呼んでいない）。呼び出しがあれば残す。

- [ ] **Step 2: ファイルを削除する**

```bash
git rm app/services/spotify_web_api/client.rb test/services/spotify_web_api_client_test.rb app/views/spotify/playlists/create.html.erb
rmdir app/services/spotify_web_api 2>/dev/null || true
```

- [ ] **Step 3: Gemfile から spotify-client を削除する**

`Gemfile` から次の行を削除する。

```ruby
gem 'spotify-client', require: 'spotify/client'
```

Run: `devbox run -- bundle install`

Expected: `Gemfile.lock` から `spotify-client` と `excon` が消える。

- [ ] **Step 4: SpotifyPlaylist の未使用 scope を削除する**

`app/models/spotify_playlist.rb` から次の行を削除する。

```ruby
  scope :stale, -> { where(synced_at: nil).or(where(synced_at: ...24.hours.ago)) }
```

- [ ] **Step 5: コントローラの未使用 private メソッドを削除する**

Step 1 で `format_seconds` に呼び出しが無いことを確認できていれば、
`app/controllers/spotify/playlists_controller.rb` から `format_seconds` を削除する。

- [ ] **Step 6: アプリが起動し全テストが通ることを確認する**

Run: `devbox run -- bin/rails runner 'puts "boot ok"'`

Expected: `boot ok`。

Run: `make minitest && make rubocop`

Expected: 全 test pass、0 offenses。

- [ ] **Step 7: コミット**

```bash
git add -A
git commit -m "デッドコードと専用依存を撤去する

- SpotifyWebApi::Client は自身のテスト以外から参照されていなかった
  （/items のパス設計と URI 組み立ては SpotifyApi::Playlist に既に存在する）
- spotify-client gem は上記ラッパー専用の依存だった
- 到達不能な create.html.erb、未使用の scope :stale / CACHE_TTL / MAX_RETRIES を削除
- rspotify gem 自体は spotify_client/*/rspotify_backend.rb が使うため #563 まで残す"
```

---

### Task 15: 移行後の検証（スナップショット差分 + 実 API 動作確認）

**目的:** 移行によって意図しない変化が起きていないことを確認し、実 API で全機能が動くことを確かめる。

**Files:**
- Create: `$SCRATCH/after/`（リポジトリ外）

**前提:** Task 5（scope 変更）と Task 12（Redis キー変更）により、**再ログインが必要**。

- [ ] **Step 1: アプリを起動する**

Run: `make up`

Expected: PostgreSQL / Redis / Rails / JS / CSS が起動する。

- [ ] **Step 2: 再ログインする**

ブラウザで `http://localhost:3000` を開き、Spotify でログインし直す。Spotify の再認可画面で
要求される権限が **「メールアドレスの表示」と「公開プレイリストの管理」の 2 つだけ**に
なっていることを確認する（保存済みライブラリの権限が消えていること）。

- [ ] **Step 3: 新しいキーで auth_hash が保存されたことを確認する**

Run: `devbox run -- bin/rails runner 'u = User.first; k = SpotifyApi::UserSession.redis_key(u.id); RedisPool.with { |r| puts "key=#{k} present=#{r.get(k).present?} ttl=#{r.ttl(k)}" }'`

Expected: `present=true`、`ttl` が 7776000（90 日）に近い正の値。

- [ ] **Step 4: 旧キーを削除する**

Run: `devbox run -- bin/rails runner 'u = User.first; RedisPool.with { |r| puts "deleted=#{r.del(u.id)}" }'`

Expected: `deleted=1`（旧キーが残っていた場合）または `deleted=0`。

- [ ] **Step 5: index のリクエスト数を実測する**

`$SCRATCH/count_requests.rb` を Write ツールで作成する。

```ruby
# index の API リクエスト数を実測する。Spotify への書き込みは行わない。
session = SpotifyApi::UserSession.find(User.first.id)

count = 0
original_get = SpotifyApi::Client.instance_method(:get)
SpotifyApi::Client.define_method(:get) do |*args, **kwargs|
  count += 1
  original_get.bind_call(self, *args, **kwargs)
end

titles = OriginalSong.playlist_titles.to_set
fetched = SpotifyApi::Playlist.all_mine(session, limit: 50)
matched = fetched.select { |p| titles.include?(p['name']) }

puts "GET requests=#{count}"
puts "playlists fetched=#{fetched.size} matched=#{matched.size}"
puts "followers key present on list items=#{fetched.first&.key?('followers')}"
```

Run: `devbox run -- bin/rails runner $SCRATCH/count_requests.rb`

Expected: `GET requests=13` 前後（613 件 ÷ 50 = 13 ページ）。**625 に近い値が出たら移行が
不完全**なので報告する。

- [ ] **Step 6: ブラウザで全機能を確認する**

以下を順に実行し、それぞれエラーが出ないことを確認する。

1. `/spotify/playlists` を開く → 一覧が表示される（DB キャッシュがあればそれが出る）
2. 「最新情報を取得」を押す → キャッシュが消えて一覧が再取得される（Task 13 の修正で
   初めて機能するようになったボタン）
3. 「曲数を更新」を押す → 進捗バーが進み、follower 数が埋まる
4. 一覧から 1 件「同期」を押す → 同期完了のメッセージが出る
5. トップページから原曲別プレイリスト更新（Windows など）を実行 → 進捗ページが進む
6. `/spotify/playlists/original_songs` → JSON がダウンロードされる
7. ログアウト → `/spotify/playlists` にアクセスするとトップへリダイレクトされる

- [ ] **Step 7: 移行後スナップショットを取得して差分を確認する**

Run: `SNAPSHOT_DIR=$SCRATCH/after devbox run -- bin/rails runner $SCRATCH/snapshot.rb`

Run: `diff <(jq -S . $SCRATCH/before/spotify_playlists.json) <(jq -S . $SCRATCH/after/spotify_playlists.json) | head -50`

Expected: 差分は「`followers` / `total` / `synced_at` / `position` が更新された」または
「レコードが増えた」のみ。**`name` や `original_song_code` の変化、レコードの消失があれば
移行のバグ**なので報告する。

Run: `diff <(jq -S . $SCRATCH/before/users.json) <(jq -S . $SCRATCH/after/users.json)`

Expected: 差分なし、または `nickname` / `image_url` が更新された分のみ（Task 6 で
既存ユーザーを更新するようにしたため）。

- [ ] **Step 8: 機密情報が git に入っていないことを確認する**

Run: `git ls-files | grep -i 'vcr\|cassette'`

Expected: 出力なし。

Run: `git grep -nE 'BQ[A-Za-z0-9_-]{25,}|AQ[A-Za-z0-9_-]{25,}' -- test/ docs/`

Expected: 出力なし。

Run: `git grep -nE '[A-Za-z0-9._%+-]+@(gmail|googlemail)\.com' -- test/ docs/ app/ lib/ config/`

Expected: 出力なし（fixture のメールアドレスは `test@example.com` のみ）。

- [ ] **Step 9: 完了条件を確認する**

Run: `grep -rn 'RSpotify' app/controllers/ app/services/`

Expected: 出力なし。

Run: `make minitest && make rubocop`

Expected: 全 test pass、0 offenses。

- [ ] **Step 10: PR を作成する**

```bash
git push -u origin feature/spotify-oauth-playlist-migration
```

PR のタイトルと本文は日本語で書き、以下を含める。

- 実測で判明した Issue 本文の前提の誤り 2 件（`email` は今も返る / `tracks` と `items` は併存）
- index のリクエスト数 625 → 13 の実測値
- 修正した実バグ（`return` 漏れ、`save_playlists_to_db` の更新漏れ、`link_to method: :delete`、
  `handle_ssl_error` / `handle_rate_limit_error` の retry 不成立、`User` の既存ユーザー更新漏れ）
- **再ログインが必要**であること（scope 変更と Redis キー変更のため）
- 別 Issue に切り出した非機能改善 5 件

PR 本文は作成前にユーザーに提示して承認を得ること（`~/.claude/rules/issue-update.md`）。

---

## Self-Review

**1. Spec coverage**

| 設計書の節 | 対応タスク |
|---|---|
| 4. 機密情報の取り扱い | Task 2（gitignore・VCR filter）、Task 15 Step 8（検証） |
| 5. Phase E 安全網 | Task 1（前スナップショット）、Task 2（webmock/VCR）、Task 15 Step 7（差分） |
| 5.4 並列実行の衝突 | Task 7 / 11 / 12 の `parallelize(workers: 1)` |
| 6.1 OmniAuth ストラテジ | Task 5 |
| 6.2 `app/models/user.rb` | Task 6 |
| 6.3 `sessions_controller` / Redis キー・TTL | Task 12 |
| 7.1 セッション取得の集約 | Task 7 |
| 7.2 置換内容（index / refresh_counts / sync_single / service / Response#dig / routes / view） | Task 4, 7, 8, 9, 10, 11, 13 |
| 7.3 follower 数の設計 | Task 7（一覧は DB 値）、Task 9（更新ボタン） |
| 7.4 リトライの統合 | Task 7, 8, 9, 10, 11（全 5 箇所を `SpotifyRetry` に集約） |
| 7.5 `save_playlists_to_db` の修正 | Task 7 |
| 7.6 原曲名のみ | Task 3（判定集約）、Task 7 / 8 / 9 / 10（各経路）、Task 8（`sync_single` の再検証） |
| 8. Phase C デッドコード撤去 | Task 14 |
| 10. 完了条件 | Task 15 |

`original_songs` の RSpotify 撤去は設計書 7.2 の表に明示が無かったが、完了条件
「`app/controllers` から RSpotify の参照が消えている」を満たすために Task 10 として追加した。

**2. Placeholder scan**

「適切にエラー処理する」「必要に応じて」等の曖昧な指示は無い。Task 5 Step 4 と Task 6 Step 3、
Task 11 Step 1 には「テストが落ちた場合の代替」を明記してあるが、これは実行時にしか
判明しない Hashie::Mash の挙動・スキーマ差異・リトライ時間に対する具体的な分岐であり、
プレースホルダではない。

**3. Type consistency**

- `spotify_session` は concern（Task 7）→ controller（Task 7-11）→ service キーワード
  `spotify_session:`（Task 11）で一貫。
- `OriginalSong.playlist_titles` / `playlist_title?` / `playlist_code_for` / `playlist_code_map`
  は Task 3 で定義し、Task 7 / 8 / 9 で同名で使用。
- `replace_playlist_tracks(playlist_id, spotify_tracks)` は controller（Task 8）と
  service（Task 11）で同じシグネチャ。
- `SpotifyApi::UserSession.redis_key(user_id)` / `TTL` は Task 12 で定義し、
  `sessions_controller` とテスト（Task 12）、Task 15 で使用。
- `SpotifyApiStubs` のメソッド名は Task 2 で定義し、Task 7 / 8 / 9 / 10 / 11 で使用。
- fixture の `PLAYLIST_TITLE_MATCHED` プレースホルダは Task 7（`me_playlists.json`）と
  Task 9（`playlist_detail.json`）で同じ置換規則。
