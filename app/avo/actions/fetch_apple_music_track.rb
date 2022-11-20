# frozen_string_literal: true

class FetchAppleMusicTrack < Avo::BaseAction
  self.name = 'Fetch apple music track'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    AppleMusicAlbum.find_each do |apple_music_album|
      AppleMusicClient::Track.fetch_album_tracks(apple_music_album)
    end
  end
end
