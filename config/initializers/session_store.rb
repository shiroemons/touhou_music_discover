# frozen_string_literal: true

# Cookie はポートで分離されないため、127.0.0.1 上で本体とワークツリーを同時に開くと
# 同じ名前のセッション Cookie を上書きし合い、ログイン状態や CSRF トークンが壊れる。
# ワークツリーでは scripts/worktree_setup が .worktree.env に固有の Cookie 名を書くので、それを使う。
if (session_cookie_key = ENV['SESSION_COOKIE_KEY'].presence)
  Rails.application.config.session_store :cookie_store, key: session_cookie_key
end
