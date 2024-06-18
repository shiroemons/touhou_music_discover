# frozen_string_literal: true

class FetchYtmusicAlbum < Avo::BaseAction
  self.name = 'Fetch ytmusic album'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    YtmusicAlbum.fetch_albums

    succeed 'Done!'
    reload
  end
end
