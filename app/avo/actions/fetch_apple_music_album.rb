# frozen_string_literal: true

class FetchAppleMusicAlbum < Avo::BaseAction
  self.name = 'Apple Musicアルバムを取得'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    master_artist_count = MasterArtist.apple_music.count
    Admin::ActionProgress.start(total: master_artist_count, message: 'Apple Musicアーティストを取得しています')
    processed_count = 0

    MasterArtist.apple_music.find_in_batches(batch_size: 25) do |master_artists|
      AppleMusicClient::Artist.fetch(master_artists.map(&:key))
      processed_count += master_artists.size
      Admin::ActionProgress.update(
        current: processed_count,
        total: master_artist_count,
        message: "Apple Musicアーティストを処理しています: #{processed_count}/#{master_artist_count}"
      )
    end

    am_artist_ids = AppleMusicArtist.pluck(:apple_music_id)
    Admin::ActionProgress.start(total: am_artist_ids.size, message: 'Apple Musicアルバムを取得しています')
    am_artist_ids.each do |am_artist_id|
      AppleMusicClient::Album.fetch_artists_albums(am_artist_id)
      Admin::ActionProgress.advance(message: "Apple MusicアーティストIDを処理しています: #{am_artist_id}")
    end

    succeed 'Done!'
    reload
  end
end
