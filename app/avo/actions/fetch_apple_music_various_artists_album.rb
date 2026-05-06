# frozen_string_literal: true

class FetchAppleMusicVariousArtistsAlbum < Avo::BaseAction
  self.name = 'Apple Music Various Artistsアルバムを取得'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    album_ids = AppleMusicAlbum::VARIOUS_ARTISTS_ALBUMS_IDS
    Admin::ActionProgress.start(total: album_ids.size, message: 'Various Artistsアルバムを取得しています')

    album_ids.each do |album_id|
      apple_music_album = AppleMusicClient::Album.fetch(album_id)
      AppleMusicClient::Track.fetch_album_tracks(apple_music_album) if apple_music_album
      Admin::ActionProgress.advance(message: "アルバムを処理しています: #{album_id}")
    end

    succeed 'Done!'
    reload
  end
end
