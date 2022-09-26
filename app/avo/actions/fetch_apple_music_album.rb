# frozen_string_literal: true

class FetchAppleMusicAlbum < Avo::BaseAction
  self.name = 'Fetch apple music album'
  self.standalone = true
  self.visible = ->(resource:, view:) { view == :index }

  def handle(_args)
    MasterArtist.apple_music.find_in_batches(batch_size: 25) do |master_artists|
      AppleMusicClient::Artist.fetch(master_artists.map(&:key))
    end

    am_artist_ids = AppleMusicArtist.pluck(:apple_music_id)
    am_artist_ids.each do |am_artist_id|
      AppleMusicClient::Album.fetch_artists_albums(am_artist_id)
    end
  end
end
