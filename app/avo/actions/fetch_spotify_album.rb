# frozen_string_literal: true

class FetchSpotifyAlbum < Avo::BaseAction
  self.name = 'Fetch spotify album'
  self.standalone = true
  self.visible = ->(resource:, view:) { view == :index }

  def handle(_args)
    SpotifyClient::Album.fetch_touhou_albums
  end
end
