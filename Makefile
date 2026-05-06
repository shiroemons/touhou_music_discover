all: help

.PHONY: setup shell versions up tui logs down restart status ps server console console-sandbox bundle \
	dbinit dbconsole migrate migrate-redo rollback dbseed upsert-original-data \
	minitest rubocop rubocop-autocorrect rubocop-autocorrect-all db-dump db-restore \
	fetch-touhou-music-with-original-songs export-touhou-music-with-original-songs \
	import-touhou-music-with-original-songs export-touhou-music export-touhou-music-slim \
	export-touhou-music-album-only export-for-algolia export-to-random-touhou-music \
	change-is-touhou-flag associate-album-with-circle export-missing-original-songs-albums \
	export-spotify export-all help

# ============================================================
# devbox環境コマンド (デフォルト)
# ============================================================

setup: ## devbox環境の初期化（bundle + yarn）
	devbox run setup

shell: ## devboxシェルに入る
	devbox shell

versions: ## 開発ツールのバージョンを表示
	@echo "=== 開発ツールのバージョン ==="
	@devbox run -- sh -c 'ruby -v && psql --version && redis-server --version && node --version && yarn --version' 2>/dev/null \
		| grep -v "東方同人音楽流通" \
		| sed 's/^ruby \([^ ]*\).*/  Ruby:       \1/' \
		| sed 's/^psql (PostgreSQL) /  PostgreSQL: /' \
		| sed 's/^Redis server v=\([^ ]*\).*/  Redis:      \1/' \
		| sed 's/^v\([0-9]\)/  Node.js:    v\1/' \
		| sed '/^[0-9]/s/^/  Yarn:       /'

up: ## 全サービスをバックグラウンドで起動（起動済みの場合はステータスを表示）
	@if devbox services ls 2>&1 | grep -q "Services running in process-compose"; then \
		echo "サービスは既に起動しています"; \
	else \
		devbox services up -b; \
	fi
	@echo ""
	@$(MAKE) --no-print-directory versions
	@echo ""
	@$(MAKE) --no-print-directory status

tui: ## 全サービスをTUIモードで起動
	devbox services up

logs: ## Railsサーバーのログを表示
	tail -f log/development.log

down: ## devboxサービスを停止
	@if devbox services ls 2>&1 | grep -q "Services running in process-compose"; then \
		devbox services stop 2>/dev/null; \
		echo "サービスを停止しました"; \
	else \
		echo "サービスは起動していません"; \
	fi

restart: ## devboxサービスを再起動
	devbox services restart

status: ## devboxサービスの状態を表示
	@if devbox services ls 2>&1 | grep -q "Services running in process-compose"; then \
		devbox services ls; \
	else \
		echo "サービスは起動していません。make up で起動できます。"; \
	fi

ps: status ## devboxサービスの状態を表示（statusのエイリアス）

server: ## Railsサーバーを起動
	devbox run server

console: ## Railsコンソールを起動
	devbox run console

console-sandbox: ## Railsコンソール（sandbox）を起動
	devbox run console:sandbox

bundle: ## bundle installを実行
	devbox run bundle

dbinit: ## データベースを初期化（drop & setup）
	devbox run db:init

dbconsole: ## データベースコンソールを起動
	devbox run db:console

migrate: ## db:migrateを実行
	devbox run db:migrate

migrate-redo: ## db:migrate:redoを実行
	devbox run db:migrate:redo

rollback: ## db:rollbackを実行
	devbox run db:rollback

dbseed: ## db:seedを実行
	devbox run db:seed

upsert-original-data: ## 原作・原曲データをupsert（追加・更新）
	devbox run upsert:originals

minitest: ## テストを実行
	devbox run test

rubocop: ## Rubocopを実行
	devbox run rubocop

rubocop-autocorrect: ## Rubocop自動修正を実行
	devbox run rubocop:fix

rubocop-autocorrect-all: ## Rubocop自動修正（全て）を実行
	devbox run rubocop:fix:all

db-dump: ## データベースのバックアップ
	devbox run db:backup

db-restore: ## データベースのリストア
	devbox run db:restore

# --- エクスポート/インポート コマンド ---

fetch-touhou-music-with-original-songs: ## 外部から原曲紐付けデータを取得し紐付けを行う
	devbox run import:fetch_touhou_music

export-touhou-music-with-original-songs: ## 原曲付きリストを出力
	devbox run export:touhou_music_with_original_songs

import-touhou-music-with-original-songs: ## 原曲付きリストを読み込み原曲紐付けを行う
	devbox run import:touhou_music_with_original_songs

export-touhou-music: ## 東方同人音楽流通 配信曲リスト出力
	devbox run export:touhou_music

export-touhou-music-slim: ## 東方同人音楽流通 配信曲リストスリム版出力
	devbox run export:touhou_music_slim

export-touhou-music-album-only: ## 東方同人音楽流通 配信アルバムリスト出力
	devbox run export:touhou_music_album_only

export-for-algolia: ## Algolia向けのJSON出力
	devbox run export:for_algolia

export-to-random-touhou-music: ## 東方サブスクランダム選曲アプリ用JSON出力
	devbox run export:to_random_touhou_music

change-is-touhou-flag: ## 原曲情報を見てis_touhouフラグを変更する
	devbox run change:is_touhou_flag

associate-album-with-circle: ## アルバムにサークルを紐付ける
	devbox run associate:album_with_circle

export-missing-original-songs-albums: ## 原曲紐づけがないアルバム一覧
	devbox run export:missing_original_songs_albums

export-spotify: ## Spotifyエクスポート
	devbox run export:spotify

export-all: ## 全てのエクスポートファイルを一括出力
	devbox run export:all

# ============================================================
# Docker環境コマンド (docker-プレフィックス)
# ============================================================

docker-init: ## [Docker] 環境を初期化
	docker compose build
	docker compose run --rm web bin/setup

docker-down: ## [Docker] docker compose down
	docker compose down

docker-logs: ## [Docker] docker composeのログを表示
	docker compose logs -f

docker-server: ## [Docker] サーバーを起動
	docker compose run --rm --service-ports web

docker-console: ## [Docker] コンソールを起動
	docker compose run --rm web bin/rails console

docker-console-sandbox: ## [Docker] コンソール（sandbox）を起動
	docker compose run --rm web bin/rails console --sandbox

docker-bundle: ## [Docker] bundle installを実行
	docker compose run --rm web bundle config set clean true
	docker compose run --rm web bundle install --jobs=4

docker-dbinit: ## [Docker] データベースを初期化
	docker compose run --rm web bin/rails db:drop db:setup

docker-dbconsole: ## [Docker] データベースコンソールを起動
	docker compose run --rm web bin/rails dbconsole

docker-migrate: ## [Docker] db:migrateを実行
	docker compose run --rm web bin/rails db:migrate

docker-migrate-redo: ## [Docker] db:migrate:redoを実行
	docker compose run --rm web bin/rails db:migrate:redo

docker-rollback: ## [Docker] db:rollbackを実行
	docker compose run --rm web bin/rails db:rollback

docker-dbseed: ## [Docker] db:seedを実行
	docker compose run --rm web bin/rails db:seed

docker-upsert-original-data: ## [Docker] 原作・原曲データをupsert
	docker compose run --rm web bin/rails runner 'load "db/seeds/originals_and_songs.rb"'

docker-minitest: ## [Docker] テストを実行
	docker compose run --rm -e RAILS_ENV=test web bin/rails db:test:prepare
	docker compose run --rm -e RAILS_ENV=test web bin/rails test

docker-rubocop: ## [Docker] Rubocopを実行
	docker compose run --rm web bundle exec rubocop

docker-rubocop-autocorrect: ## [Docker] Rubocop自動修正を実行
	docker compose run --rm web bundle exec rubocop --autocorrect

docker-rubocop-autocorrect-all: ## [Docker] Rubocop自動修正（全て）を実行
	docker compose run --rm web bundle exec rubocop --autocorrect-all

docker-bash: ## [Docker] webコンテナのbashに入る
	docker compose run --rm web bash

docker-db-dump: ## [Docker] データベースのバックアップ
	mkdir -p tmp/data
	docker compose exec postgres-18 pg_dump -Fc --no-owner -v -d postgres://postgres:@localhost/touhou_music_discover_development -f /tmp/data/dev.bak

docker-db-restore: ## [Docker] データベースのリストア
	@if test -f ./tmp/dev.bak; then \
		docker compose exec postgres-18 pg_restore --no-privileges --no-owner --clean -v -d postgres://postgres:@localhost/touhou_music_discover_development /tmp/data/dev.bak; \
	else \
		echo "Error: ./tmp/dev.bak does not exist."; \
		exit 1; \
	fi

docker-fetch-touhou-music-with-original-songs: ## [Docker] 外部から原曲紐付けデータを取得し紐付けを行う
	docker compose run --rm web bin/rails touhou_music_discover:import:fetch_touhou_music_with_original_songs

docker-export-touhou-music-with-original-songs: ## [Docker] 原曲付きリストを出力
	docker compose run --rm web bin/rails touhou_music_discover:export:touhou_music_with_original_songs

docker-import-touhou-music-with-original-songs: ## [Docker] 原曲付きリストを読み込み原曲紐付けを行う
	docker compose run --rm web bin/rails touhou_music_discover:import:touhou_music_with_original_songs

docker-export-touhou-music: ## [Docker] 配信曲リスト出力
	docker compose run --rm web bin/rails touhou_music_discover:export:touhou_music

docker-export-touhou-music-slim: ## [Docker] 配信曲リストスリム版出力
	docker compose run --rm web bin/rails touhou_music_discover:export:touhou_music_slim

docker-export-touhou-music-album-only: ## [Docker] 配信アルバムリスト出力
	docker compose run --rm web bin/rails touhou_music_discover:export:touhou_music_album_only

docker-export-for-algolia: ## [Docker] Algolia向けのJSON出力
	docker compose run --rm web bin/rails touhou_music_discover:export:for_algolia

docker-export-to-random-touhou-music: ## [Docker] 東方サブスクランダム選曲アプリ用JSON出力
	docker compose run --rm web bin/rails touhou_music_discover:export:to_random_touhou_music

docker-change-is-touhou-flag: ## [Docker] is_touhouフラグ変更
	docker compose run --rm web bin/rails touhou_music_discover:change_is_touhou_flag

docker-associate-album-with-circle: ## [Docker] アルバムにサークルを紐付ける
	docker compose run --rm web bin/rails touhou_music_discover:associate_album_with_circle

docker-export-missing-original-songs-albums: ## [Docker] 原曲紐づけがないアルバム一覧
	docker compose run --rm web bin/rails touhou_music_discover:export:missing_original_songs_albums

docker-export-spotify: ## [Docker] Spotifyエクスポート
	docker compose run --rm web bin/rails touhou_music_discover:export:spotify

docker-export-all: ## [Docker] 全エクスポート一括出力
	docker compose run --rm web bin/rails touhou_music_discover:export:touhou_music_with_original_songs
	docker compose run --rm web bin/rails touhou_music_discover:export:touhou_music
	docker compose run --rm web bin/rails touhou_music_discover:export:touhou_music_slim
	docker compose run --rm web bin/rails touhou_music_discover:export:touhou_music_album_only
	docker compose run --rm web bin/rails touhou_music_discover:export:spotify
	docker compose run --rm web bin/rails touhou_music_discover:export:missing_original_songs_albums

help: ## ヘルプを表示
	@echo "=== devbox環境コマンド ==="
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -v '\[Docker\]' | sort | awk -F':.*?## ' '{printf "\033[36m%-45s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "=== Docker環境コマンド ==="
	@grep -E '^[a-zA-Z_-]+:.*?## \[Docker\].*$$' $(MAKEFILE_LIST) | sort | awk -F':.*?## ' '{printf "\033[33m%-45s\033[0m %s\n", $$1, $$2}'
