# frozen_string_literal: true

class BulkRetrieval < Avo::BaseAction
  self.name = '一括取得'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(**_args)
    Admin::ActionProgress.start(total: 7, message: 'Spotify アルバムを取得しています')

    # Spotify
    SpotifyClient::Album.fetch_touhou_albums
    Admin::ActionProgress.advance(message: 'Apple Music アルバムとトラックを取得しています')

    # Apple Music
    AppleMusicTrack.fetch_tracks_and_albums
    Admin::ActionProgress.advance(message: 'YouTube Music アルバムを取得しています')

    # YouTube Music
    YtmusicAlbum.fetch_albums
    Admin::ActionProgress.advance(message: 'YouTube Music トラックを取得しています')
    YtmusicTrack.fetch_tracks
    Admin::ActionProgress.advance(message: 'LINE MUSIC アルバムを取得しています')

    # LINE MUSIC
    LineMusicAlbum.fetch_albums
    Admin::ActionProgress.advance(message: 'LINE MUSIC トラックを取得しています')
    LineMusicTrack.fetch_tracks
    Admin::ActionProgress.advance(message: 'サークルを設定しています')

    # Set Circle
    CircleAssignmentService.new.assign_missing
    Admin::ActionProgress.advance(message: '一括取得が完了しました')
  end
end
