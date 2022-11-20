# frozen_string_literal: true

class FetchAppleMusicTrackByIsrc < Avo::BaseAction
  self.name = 'Fetch apple music track by isrc'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    Track.missing_apple_music_tracks.find_each do |track|
      AppleMusicClient::Track.fetch_tracks_by_isrc(track.isrc)
    end
  end
end
