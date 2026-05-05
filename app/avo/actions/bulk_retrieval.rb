# frozen_string_literal: true

class BulkRetrieval < Avo::BaseAction
  self.name = '一括取得'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(**_args)
    # Spotify
    SpotifyClient::Album.fetch_touhou_albums

    # Apple Music
    AppleMusicTrack.fetch_tracks_and_albums

    # YouTube Music
    YtmusicAlbum.fetch_albums
    YtmusicTrack.fetch_tracks

    # LINE MUSIC
    LineMusicAlbum.fetch_albums
    LineMusicTrack.fetch_tracks

    # Set Circle
    CircleAssignmentService.new.assign_missing
  end
end
