# frozen_string_literal: true

module SpotifyClient
  class Album
    LIMIT = 50

    def self.fetch_artists_albums(artist_id)
      return if artist_id.blank?

      artist = RSpotify::Artist.find(artist_id)
      offset = 0
      loop do
        spotify_albums = artist.albums(limit: LIMIT, offset: offset)
        spotify_albums.each do |album|
          save_album(album)
        end
        offset += LIMIT

        # 429 Too Many Requests対策
        sleep 0.5

        break if spotify_albums.count < LIMIT
      end
    end

    def self.save_album(spotify_album)
      next if spotify_album.label != ::Album::TOUHOU_MUSIC_LABEL

      jan_code = spotify_album.external_ids['upc']
      album = ::Album.find_or_create_by!(jan_code: jan_code)

      payload = spotify_album.as_json
      payload.delete('tracks_cache')

      ::SpotifyAlbum.find_or_create_by!(
        album_id: album.id,
        spotify_id: spotify_album.id,
        album_type: spotify_album.album_type,
        name: spotify_album.name,
        label: spotify_album.label,
        url: spotify_album.external_urls['spotify'],
        release_date: spotify_album.release_date,
        total_tracks: spotify_album.total_tracks,
        payload: payload
      )
    end
  end
end
