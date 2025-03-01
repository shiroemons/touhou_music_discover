# frozen_string_literal: true

class FetchLineMusicAlbum < Avo::BaseAction
  self.name = 'LINE MUSIC アルバムを取得'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    LineMusicAlbum.fetch_albums

    succeed 'Done!'
    reload
  end
end
