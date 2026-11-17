# モジュール共通の設定。モジュールのレシピはモジュールファイルのディレクトリで実行されるため、
# リポジトリのルートに戻してから scripts/ や devbox を呼ぶ。

set quiet
set shell := ["bash", "-eo", "pipefail", "-c"]
set working-directory := '..'
