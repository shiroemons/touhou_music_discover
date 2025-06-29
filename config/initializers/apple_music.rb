# frozen_string_literal: true

require Rails.root.join('lib/apple_music')

AppleMusic.configure do |config|
  config.secret_key = ENV.fetch('APPLE_MUSIC_SECRET_KEY', nil)
  config.team_id    = ENV.fetch('APPLE_MUSIC_TEAM_ID', nil)
  config.music_id   = ENV.fetch('APPLE_MUSIC_MUSIC_ID', nil)
  config.storefront = 'jp'
end
