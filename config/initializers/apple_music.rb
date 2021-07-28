# frozen_string_literal: true

AppleMusic.configure do |config|
  config.secret_key = ENV['APPLE_MUSIC_SECRET_KEY']
  config.team_id    = ENV['APPLE_MUSIC_TEAM_ID']
  config.music_id   = ENV['APPLE_MUSIC_MUSIC_ID']
  config.storefront = 'jp'
end
