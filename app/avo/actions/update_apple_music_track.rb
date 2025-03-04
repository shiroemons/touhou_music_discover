# frozen_string_literal: true

class UpdateAppleMusicTrack < Avo::BaseAction
  self.name = 'Apple Music トラックを更新'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    AppleMusicTrack.eager_load(:album, :apple_music_album, :track).find_in_batches(batch_size: 50) do |apple_music_tracks|
      AppleMusicClient::Track.update_tracks(apple_music_tracks)
      sleep 0.5
    end

    succeed 'Done!'
    reload
  end
end
