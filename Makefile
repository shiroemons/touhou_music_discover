all: help

init: ## Initialize environment
	docker compose build
	docker compose run --rm web bin/setup

down: ## Do docker compose down
	docker compose down

logs: ## Tail docker compose logs
	docker compose logs -f

server: ## Run server
	docker compose run --rm --service-ports web

console: ## Run console
	docker compose run --rm web bin/rails console

console-sandbox: ## Run console(sandbox)
	docker compose run --rm web bin/rails console --sandbox

bundle: ## Run bundle install
	docker compose run --rm web bundle config set clean true
	docker compose run --rm web bundle install --jobs=4

dbinit: ## Initialize database
	docker compose run --rm web bin/rails db:drop db:setup

dbconsole: ## Run dbconsole
	docker compose run --rm web bin/rails dbconsole

migrate: ## Run db:migrate
	docker compose run --rm web bin/rails db:migrate

migrate-redo: ## Run db:migrate:redo
	docker compose run --rm web bin/rails db:migrate:redo

rollback: ## Run db:rollback
	docker compose run --rm web bin/rails db:rollback

dbseed: ## Run db:seed
	docker compose run --rm web bin/rails db:seed

minitest: ## Run test
	docker compose run --rm -e RAILS_ENV=test web bin/rails db:test:prepare
	docker compose run --rm -e RAILS_ENV=test web bin/rails test

rubocop: ## Run rubocop
	docker compose run --rm web bundle exec rubocop

rubocop-autocorrect: ## Run rubocop autocorrect
	docker compose run --rm web bundle exec rubocop --autocorrect

rubocop-autocorrect-all: ## Run rubocop autocorrect-all
	docker compose run --rm web bundle exec rubocop --autocorrect-all

bash: ## Run bash in web container
	docker compose run --rm web bash

db-dump: ## db dump
	mkdir -p tmp/data
	docker compose exec postgres-16 pg_dump -Fc --no-owner -v -d postgres://postgres:@localhost/touhou_music_discover_development -f /tmp/data/dev.bak

db-restore: ## db restore
	@if test -f ./tmp/dev.bak; then \
		docker compose exec postgres-16 pg_restore --no-privileges --no-owner --clean -v -d postgres://postgres:@localhost/touhou_music_discover_development /tmp/data/dev.bak; \
	else \
		echo "Error: ./tmp/dev.bak does not exist."; \
		exit 1; \
	fi

# 共通コマンド
fetch-touhou-music-with-original-songs: ## 外部から原曲紐付けデータを取得し紐付けを行う
	docker compose run --rm web bin/rails touhou_music_discover:import:fetch_touhou_music_with_original_songs

export-touhou-music-with-original-songs: ## 原曲付きリストを出力
	docker compose run --rm web bin/rails touhou_music_discover:export:touhou_music_with_original_songs

import-touhou-music-with-original-songs: ## 原曲付きリストを読み込み原曲紐付けを行う
	docker compose run --rm web bin/rails touhou_music_discover:import:touhou_music_with_original_songs

export-touhou-music: ## 東方同人音楽流通 配信曲リスト出力
	docker compose run --rm web bin/rails touhou_music_discover:export:touhou_music

export-touhou-music-slim: ## 東方同人音楽流通 配信曲リストスリム版出力
	docker compose run --rm web bin/rails touhou_music_discover:export:touhou_music_slim

export-touhou-music-album-only: ## 東方同人音楽流通 配信アルバムリスト出力
	docker compose run --rm web bin/rails touhou_music_discover:export:touhou_music_album_only

export-for-algolia: ## Algolia向けのJSON出力
	docker compose run --rm web bin/rails touhou_music_discover:export:for_algolia

export-to-random-touhou-music: ## 東方サブスクランダム選曲アプリ用JSON出力
	docker compose run --rm web bin/rails touhou_music_discover:export:to_random_touhou_music

change-is-touhou-flag: ## 原曲情報を見て、is_touhouフラグを変更する
	docker compose run --rm web bin/rails touhou_music_discover:change_is_touhou_flag

associate-album-with-circle: ## アルバムにサークルを紐付ける
	docker compose run --rm web bin/rails touhou_music_discover:associate_album_with_circle

export-missing-original-songs-albums: ## 原曲紐づけがないアルバム一覧
	docker compose run --rm web bin/rails touhou_music_discover:export:missing_original_songs_albums

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk -F':.*?## ' '{printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'
