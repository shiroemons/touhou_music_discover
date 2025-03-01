# frozen_string_literal: true

class FetchAppleMusicTrack < Avo::BaseAction
  self.name = 'Apple Music トラックを取得'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    AppleMusicAlbum.find_each do |apple_music_album|
      AppleMusicClient::Track.fetch_album_tracks(apple_music_album)
    end

    succeed 'Done!'
    reload
  end
end
