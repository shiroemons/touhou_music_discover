# frozen_string_literal: true

class FetchMissingSpotifyAlbumByAppleMusicJan < Avo::BaseAction
  self.name = 'Apple Music JANでSpotifyアルバムを補完'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    progress_callback = lambda do |result, album|
      next unless (result[:processed] % 5).zero? || result[:processed] == result[:total] || result[:rate_limited]

      inform "Spotify JAN補完: #{result[:processed]}/#{result[:total]} JAN #{album.jan_code}"
    end

    result = SpotifyClient::Album.fetch_missing_albums_by_apple_music_jan(progress_callback:)

    message = "処理完了: 作成#{result[:created]}件, スキップ#{result[:skipped]}件, 未検出#{result[:missing]}件, エラー#{result[:errors]}件"
    if result[:rate_limited]
      retry_after = result[:retry_after].presence || '不明'
      message = "#{message}, レート制限で中断(Retry-After: #{retry_after}秒)"
    end

    succeed message
    reload
  end
end
