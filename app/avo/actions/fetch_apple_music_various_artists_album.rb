# frozen_string_literal: true

class FetchAppleMusicVariousArtistsAlbum < Avo::BaseAction
  self.name = 'Fetch apple music various artists album'
  self.standalone = true
  self.visible = ->(resource:, view:) { view == :index }

  def handle(_args)
    AppleMusicAlbum::VARIOUS_ARTISTS_ALBUMS_IDS.each do |album_id|
      apple_music_album = AppleMusicClient::Album.fetch(album_id)
      AppleMusicClient::Track.fetch_album_tracks(apple_music_album) if apple_music_album
    end
  end
end
