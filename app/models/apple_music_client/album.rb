# frozen_string_literal: true

module AppleMusicClient
  LIMIT = 100

  class Album
    def self.fetch(album_id)
      return if AppleMusicAlbum.exists?(apple_music_id: album_id)

      am_album = AppleMusic::Album.find(album_id)
      AppleMusicAlbum.save_album(am_album)
    end

    def self.fetch_artists_albums(am_artist_id)
      am_albums = fetch_albums(am_artist_id)
      return unless am_albums.respond_to?(:each)

      am_albums.each do |am_album|
        AppleMusicAlbum.save_album(am_album)
      end
    end

    def self.fetch_albums(artist_id)
      am_albums = []
      offset = 0
      loop do
        albums = AppleMusic::Artist.get_relationship(artist_id, :albums, limit: LIMIT, offset:)
        am_albums.push(*albums)
        break if albums.size < LIMIT

        offset += LIMIT
      end
      am_albums
    rescue AppleMusic::ApiError => e
      puts artist_id
      Rails.logger.warn e
    end

    def self.update_albums(apple_music_albums)
      ids = apple_music_albums.map(&:apple_music_id)
      am_albums = AppleMusic::Album.list(ids:)
      am_albums.each do |am_album|
        apple_music_album = apple_music_albums.find { _1.apple_music_id == am_album.id }
        apple_music_album&.update(
          name: am_album.name,
          url: am_album.url,
          total_tracks: am_album.track_count,
          payload: am_album.as_json
        )
      end
    end
  end
end
