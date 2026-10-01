---
name: worktree
description: このリポジトリでワークツリーを作成・利用・片付けるときの手順。git wt でブランチ用のワークツリーを作るとき、ワークツリーでサービス起動・DB操作・テストを行うとき、作業が終わってワークツリーを削除するときに使う。
---

# ワークツリーでの並行開発

## 仕組み

- ワークツリーごとに Rails / PostgreSQL / Redis / process-compose を専用のポートで起動する。本体のチェックアウトは従来どおり 3000 / 5432 / 6379 / 53177 を使う
- ポートは `scripts/worktree_registry` が 34000〜35999 から 10 ポート単位のブロックで割り当てる。ブロックの先頭が Rails、+1 が PostgreSQL、+2 が Redis、+3 が process-compose
- 割り当ての台帳はユーザー単位（`~/.local/state/worktree-ports/registry.tsv`）で、他のリポジトリのワークツリーとも重ならない
- 割り当てたポートは `.worktree.env` に書かれ、devbox の init_hook と Taskfile が読み込む
- DB はワークツリー専用の PostgreSQL に置く。作成時に本体の開発DBをコピーし、Solid Queue のキューDBは空で作る

## 作成する

1. 初回だけ、本体で `task worktree:config` を実行する。`git config --local --get-regexp '^wt\.'` に `wt.hook` があれば設定済み
2. 本体で `git wt --nocd <branch>` を実行する。ブランチ名は英語にする（例: `feature/...`、`fix/...`）。ワークツリーは `.worktrees/<branch>` にできる
3. `wt.hook` でセットアップが自動で走る（20 秒前後）。最後に表示される Rails の URL とポートを確認する
4. セットアップが失敗したら、原因を直してからワークツリー内で `task worktree:setup` を実行し直す。何度実行してもよく、コピー済みの DB は残る
5. git wt 以外（`git worktree add`、Claude Code の EnterWorktree、Orca など）で作ったワークツリーでは、作業を始める前にワークツリー内で `task worktree:setup` を実行する

## 作業中

- コマンドはワークツリーのディレクトリで実行する。本体のディレクトリに移動して編集しない
- `task up` / `task health` / `task test` / `devbox run -- bin/rails <task>` は本体と同じように使える。ポートは自動で切り替わる
- URL とポートは `task health` か `task worktree:list` で確認する
- ポート番号（3000 / 5432 / 6379 / 53177 / 34xxx）をコマンドやコードに直接書かない。`PORT` / `PGPORT` / `REDIS_PORT` / `DEVBOX_PC_PORT_NUM` を使う
- `devbox services` を直接使うより `task` を使う。直接使う場合は `--env DEVBOX_PC_PORT_NUM="$(scripts/worktree_env DEVBOX_PC_PORT_NUM 53177)"` を付ける
- `.worktree.env` は手で編集しない。ポートを変えたいときは、ワークツリーを作り直す
- ワークツリーの DB は捨ててよいコピー。本体の DB とサービスには書き込まない
- マイグレーションを追加したら、ワークツリーで `task db:migrate` を実行する。セットアップの最後に「未適用のマイグレーションがあります」と出た場合も同じ
- 本体の最新データが必要になったら `task worktree:db:copy` を実行する。ワークツリーの開発DBを上書きするので、ユーザーに確認してから実行する
- 他のワークツリーのファイルやサービスには触らない
- セッション Cookie の名前はワークツリーごとに分かれている（`SESSION_COOKIE_KEY`）ので、本体とワークツリーを同じブラウザで同時に開いてよい
- Spotify のログイン情報はワークツリーごとの Redis に保存されるので、ログインが必要な機能（プレイリスト操作など）はワークツリーのポートでログインし直す。redirect URI は `http://127.0.0.1:<Railsのポート>/auth/spotify/callback` になる。ダッシュボードはポートなしの登録を受け付けないため、`:3000` と `:34000` / `:34010` / `:34020` / `:34030` / `:34040` だけを登録している。それ以外のポートではログインに失敗するので、使い終わったワークツリーを片付けて低いポートを空けておく

## 片付ける

作業が終わったら（PR を作成して push した、またはユーザーが破棄を指示した）、そのワークツリーを必ず片付ける。

1. ワークツリーで `git status --short` を実行し、未コミットの変更がないことを確認する。`git log @{u}..` で未 push のコミットがないことも確認する。残っていれば、コミットして push するか、破棄してよいかユーザーに確認する
2. ワークツリーで `task down` を実行してサービスを止める
3. 本体のディレクトリで `git wt -d <branch>` を実行する
   - 削除前に `wt.deletehook` が走り、サービスの停止とポートの割り当ての解放を行う
   - 変更が残っていると削除を拒否されるので、手順 1 に戻る
   - ブランチが未マージなら、ワークツリーだけ削除されてブランチは残る（PR のために残してよい）
   - `git wt -D` は未コミットの変更ごとブランチも削除する。ユーザーの指示があるときだけ使う
4. git wt 以外で作ったワークツリーは、ワークツリー内で `scripts/worktree_teardown` を実行してから、作成したツールの方法で削除する（`git worktree remove <path>` など）
5. 本体で `task worktree:list` を実行し、削除したワークツリーが一覧に残っていないことを確認する。`scripts/worktree_registry list` に割り当てが残っていても、ディレクトリが消えていれば次の割り当て時に自動で解放される
