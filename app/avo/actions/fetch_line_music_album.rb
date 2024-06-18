# frozen_string_literal: true

class FetchLineMusicAlbum < Avo::BaseAction
  self.name = 'Fetch line music album'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    LineMusicAlbum.fetch_albums

    succeed 'Done!'
    reload
  end
end
