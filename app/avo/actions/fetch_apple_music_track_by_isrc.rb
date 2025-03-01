# frozen_string_literal: true

class FetchAppleMusicTrackByIsrc < Avo::BaseAction
  self.name = 'ISRCからApple Music トラックを取得'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    Track.missing_apple_music_tracks.find_each do |track|
      AppleMusicClient::Track.fetch_tracks_by_isrc(track.isrc)
    end

    succeed 'Done!'
    reload
  end
end
