import 'settings.just'

# データベースを初期化（drop & setup）
init:
    devbox run db:init

# データベースコンソールを起動
console:
    devbox run db:console

# db:migrateを実行
migrate:
    devbox run db:migrate

# db:migrate:redoを実行
migrate-redo:
    devbox run db:migrate:redo

# db:rollbackを実行
rollback:
    devbox run db:rollback

# db:seedを実行
seed:
    devbox run db:seed

# 圧縮した日付付きファイルでデータベースをバックアップ
backup:
    devbox run db:backup

# バックアップを原子的にリストア（BACKUP_FILE / RESTORE_DB で指定）
restore:
    devbox run db:restore
