# frozen_string_literal: true

class FetchYtmusicTrack < Avo::BaseAction
  self.name = 'Fetch ytmusic track'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    YtmusicTrack.fetch_tracks

    succeed 'Done!'
    reload
  end
end
