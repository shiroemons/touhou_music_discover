# frozen_string_literal: true

require 'omniauth'
require 'rspotify/oauth'

# OmniAuth 2.0以降のCSRF対策設定
OmniAuth.config.allowed_request_methods = %i[post get]

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :spotify, ENV.fetch('SPOTIFY_CLIENT_ID', nil), ENV.fetch('SPOTIFY_CLIENT_SECRET', nil), scope: 'user-read-email playlist-modify-public user-library-read user-library-modify'
end
