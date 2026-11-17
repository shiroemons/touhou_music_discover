import 'settings.just'

# git wt でワークツリーを作成・削除したときにセットアップ・停止が走るよう、このリポジトリの git config を設定
config:
    scripts/worktree_config

# 現在のワークツリーにポートを割り当て、本体の開発DBをコピー（git wt 以外で作ったワークツリー用）
setup:
    scripts/worktree_setup

# 現在のワークツリーの開発DBを、本体の開発DBで置き換える
[confirm("ワークツリーの開発DBを本体の開発DBで上書きします。続けますか？")]
db-copy:
    WORKTREE_DB_RECOPY=1 scripts/worktree_setup

# ワークツリーごとの割り当てポートを一覧表示
list:
    scripts/worktree_list
