# frozen_string_literal: true

class UpdateAppleMusicTrack < Avo::BaseAction
  self.name = 'Apple Music トラックを更新'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    count = 0
    total_count = AppleMusicTrack.count
    Admin::ActionProgress.start(total: total_count, message: 'Apple Musicトラックを更新しています')

    AppleMusicTrack.eager_load(:album, :apple_music_album, :track).find_in_batches(batch_size: 50) do |apple_music_tracks|
      AppleMusicClient::Track.update_tracks(apple_music_tracks)
      count += apple_music_tracks.size
      Admin::ActionProgress.update(
        current: count,
        total: total_count,
        message: "Apple Musicトラックを更新しています: #{count}/#{total_count}"
      )
      sleep 0.5
    end

    succeed 'Done!'
    reload
  end
end
