# frozen_string_literal: true

class FetchSpotifyAlbum < Avo::BaseAction
  self.name = 'Spotify アルバムを取得'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    SpotifyClient::Album.fetch_touhou_albums

    succeed 'Done!'
    reload
  end
end
