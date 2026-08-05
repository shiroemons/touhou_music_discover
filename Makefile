# Make互換ラッパー
# タスク定義はTaskfile.ymlを正本とし、このファイルは移行期間中だけ残します。

.DEFAULT_GOAL := help

DEVBOX_PC_PORT_NUM ?= 53177

COMPAT_TARGETS := setup shell versions up tui logs down restart status ps health doctor recover recover-force kill-orphan-ports server console console-sandbox bundle \
	dbinit dbconsole migrate migrate-redo rollback dbseed upsert-original-data \
	minitest rubocop rubocop-autocorrect rubocop-autocorrect-all db-dump db-restore \
	fetch-touhou-music-with-original-songs export-touhou-music-with-original-songs \
	import-touhou-music-with-original-songs export-touhou-music export-touhou-music-slim \
	export-touhou-music-album-only export-for-algolia export-to-random-touhou-music \
	change-is-touhou-flag associate-album-with-circle export-missing-original-songs-albums \
	export-spotify export-all

.PHONY: all help $(COMPAT_TARGETS)

all: help

help:
	@task --list

$(COMPAT_TARGETS):
	@target="$@"; \
	case "$$target" in \
		console-sandbox) task_name="console:sandbox" ;; \
		dbinit) task_name="db:init" ;; \
		dbconsole) task_name="db:console" ;; \
		migrate) task_name="db:migrate" ;; \
		migrate-redo) task_name="db:migrate:redo" ;; \
		rollback) task_name="db:rollback" ;; \
		dbseed) task_name="db:seed" ;; \
		db-dump) task_name="db:backup" ;; \
		db-restore) task_name="db:restore" ;; \
		upsert-original-data) task_name="data:upsert-originals" ;; \
		minitest) task_name="test" ;; \
		rubocop) task_name="lint" ;; \
		rubocop-autocorrect) task_name="lint:fix" ;; \
		rubocop-autocorrect-all) task_name="lint:fix:all" ;; \
		fetch-touhou-music-with-original-songs) task_name="import:fetch-touhou-music" ;; \
		export-touhou-music-with-original-songs) task_name="export:touhou-music-with-original-songs" ;; \
		import-touhou-music-with-original-songs) task_name="import:touhou-music-with-original-songs" ;; \
		export-touhou-music) task_name="export:touhou-music" ;; \
		export-touhou-music-slim) task_name="export:touhou-music-slim" ;; \
		export-touhou-music-album-only) task_name="export:touhou-music-album-only" ;; \
		export-for-algolia) task_name="export:for-algolia" ;; \
		export-to-random-touhou-music) task_name="export:to-random-touhou-music" ;; \
		change-is-touhou-flag) task_name="change:is-touhou-flag" ;; \
		associate-album-with-circle) task_name="associate:album-with-circle" ;; \
		export-missing-original-songs-albums) task_name="export:missing-original-songs-albums" ;; \
		export-spotify) task_name="export:spotify" ;; \
		export-all) task_name="export:all" ;; \
		*) task_name="$$target" ;; \
	esac; \
	if ! command -v task >/dev/null 2>&1; then \
		echo "Taskが見つかりません。mise installを実行してください。" >&2; \
		exit 1; \
	fi; \
	DEVBOX_PC_PORT_NUM="$(DEVBOX_PC_PORT_NUM)" task "$$task_name"
