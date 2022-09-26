# frozen_string_literal: true

class UpdateAppleMusicTrack < Avo::BaseAction
  self.name = 'Update apple music track'
  self.standalone = true
  self.visible = ->(resource:, view:) { view == :index }

  def handle(_args)
    AppleMusicTrack.eager_load(:album, :apple_music_album, :track).find_in_batches(batch_size: 50) do |apple_music_tracks|
      AppleMusicClient::Track.update_tracks(apple_music_tracks)
      sleep 0.5
    end
  end
end
