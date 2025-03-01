# frozen_string_literal: true

class FetchLineMusicTrack < Avo::BaseAction
  self.name = 'LINE MUSIC トラックを取得'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    LineMusicTrack.fetch_tracks

    succeed 'Done!'
    reload
  end
end
