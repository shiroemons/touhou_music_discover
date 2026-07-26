# frozen_string_literal: true

require Rails.root.join('lib/spotify_api')

# ここではアクセストークンを取得しない。
#
# 起動時にネットワークI/Oを走らせると、Spotify 側の障害時に bin/rails の
# あらゆるコマンドが遅くなる・起動できなくなるため、トークンは最初の
# API 呼び出し時に SpotifyApi::Config#access_token が遅延取得する。
SpotifyApi.configure do |config|
  config.client_id           = ENV.fetch('SPOTIFY_CLIENT_ID', nil)
  config.client_secret       = ENV.fetch('SPOTIFY_CLIENT_SECRET', nil)
  config.market              = 'JP'
  config.search_limit        = ENV.fetch('SPOTIFY_SEARCH_LIMIT', 50).to_i
  config.playlist_items_path = ENV.fetch('SPOTIFY_PLAYLIST_ITEMS_PATH', 'tracks')
end
