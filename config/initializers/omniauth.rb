# frozen_string_literal: true

require 'omniauth'
require 'rspotify/oauth'

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :spotify, ENV.fetch('SPOTIFY_CLIENT_ID', nil), ENV.fetch('SPOTIFY_CLIENT_SECRET', nil), scope: 'user-read-email playlist-modify-public user-library-read user-library-modify'
end
