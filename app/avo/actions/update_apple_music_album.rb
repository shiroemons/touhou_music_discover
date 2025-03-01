# frozen_string_literal: true

class UpdateAppleMusicAlbum < Avo::BaseAction
  self.name = 'Apple Music アルバムを更新'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    AppleMusicAlbum.eager_load(:album).find_in_batches(batch_size: 20) do |apple_music_albums|
      AppleMusicClient::Album.update_albums(apple_music_albums)
      sleep 0.5
    end

    succeed 'Done!'
    reload
  end
end
