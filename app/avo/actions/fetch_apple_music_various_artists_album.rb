# frozen_string_literal: true

class FetchAppleMusicVariousArtistsAlbum < Avo::BaseAction
  self.name = 'Apple Music Various Artistsアルバムを取得'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    AppleMusicAlbum::VARIOUS_ARTISTS_ALBUMS_IDS.each do |album_id|
      apple_music_album = AppleMusicClient::Album.fetch(album_id)
      AppleMusicClient::Track.fetch_album_tracks(apple_music_album) if apple_music_album
    end

    succeed 'Done!'
    reload
  end
end
