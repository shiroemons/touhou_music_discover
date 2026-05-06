# frozen_string_literal: true

class FetchAppleMusicTrackByIsrc < Avo::BaseAction
  self.name = 'ISRCからApple Music トラックを取得'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    total_count = Track.missing_apple_music_tracks.count
    Admin::ActionProgress.start(total: total_count, message: 'ISRCからApple Musicトラックを取得しています')

    Track.missing_apple_music_tracks.find_each do |track|
      AppleMusicClient::Track.fetch_tracks_by_isrc(track.isrc)
      Admin::ActionProgress.advance(message: "ISRCを処理しています: #{track.isrc}")
    end

    succeed 'Done!'
    reload
  end
end
