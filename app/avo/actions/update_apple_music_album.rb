# frozen_string_literal: true

class UpdateAppleMusicAlbum < Avo::BaseAction
  self.name = 'Apple Music アルバムを更新'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    count = 0
    total_count = AppleMusicAlbum.count
    Admin::ActionProgress.start(total: total_count, message: 'Apple Musicアルバムを更新しています')

    AppleMusicAlbum.eager_load(:album).find_in_batches(batch_size: 20) do |apple_music_albums|
      AppleMusicClient::Album.update_albums(apple_music_albums)
      count += apple_music_albums.size
      Admin::ActionProgress.update(
        current: count,
        total: total_count,
        message: "Apple Musicアルバムを更新しています: #{count}/#{total_count}"
      )
      sleep 0.5
    end

    succeed 'Done!'
    reload
  end
end
