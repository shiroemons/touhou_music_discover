# frozen_string_literal: true

# RSpotify のクライアントクレデンシャル認証。
#
# Application クラス本体で実行するとタイムアウトの無いネットワークI/Oが
# 起動時に走り、Spotify 側の障害時に bin/rails のあらゆるコマンドが
# 起動できなくなるため、after_initialize に移している。
Rails.application.config.after_initialize do
  next if Rails.env.test?

  client_id = ENV.fetch('SPOTIFY_CLIENT_ID', nil)
  client_secret = ENV.fetch('SPOTIFY_CLIENT_SECRET', nil)
  next if client_id.blank? || client_secret.blank?

  begin
    RSpotify.authenticate(client_id, client_secret)
  rescue StandardError => e
    Rails.logger.error("[rspotify] client credentials authentication failed: #{e.class}: #{e.message}")
  end
end
