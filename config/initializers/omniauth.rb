# frozen_string_literal: true

require 'omniauth'
require 'rspotify/oauth'
require "#{Rails.root}/lib/token_verifier.rb"

OmniAuth.config.request_validation_phase = TokenVerifier.new

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :spotify, ENV.fetch('SPOTIFY_CLIENT_ID', nil), ENV.fetch('SPOTIFY_CLIENT_SECRET', nil), scope: 'user-read-email playlist-modify-public user-library-read user-library-modify'
end
