# frozen_string_literal: true

require 'omniauth'
require Rails.root.join('lib/omniauth/strategies/spotify')

# OmniAuth 2.0以降のCSRF対策設定
OmniAuth.config.allowed_request_methods = %i[post]

# OmniAuth はコールバック URL（Spotify に送る redirect_uri）のホストを Rack::Request#host から取り、
# Host / X-Forwarded-Host に加えて Forwarded ヘッダーも読む。production の config.hosts
# （HostAuthorization）は Forwarded を検証しないため、OmniAuth 側でも同じ APP_HOST に限定する
# （GHSA-m27g-v28p-f9fx）。development は RAILS_BIND_ADDRESS で LAN 上のホスト名からも
# 開けるため制限しない。APP_HOST の未設定は config/environments/production.rb が起動時に弾く。
OmniAuth.config.allowed_hosts = [ENV.fetch('APP_HOST').strip] if Rails.env.production?

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
