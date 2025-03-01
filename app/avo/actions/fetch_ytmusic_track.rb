# frozen_string_literal: true

class FetchYtmusicTrack < Avo::BaseAction
  self.name = 'YouTube Music トラックを取得'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    YtmusicTrack.fetch_tracks

    succeed 'Done!'
    reload
  end
end
