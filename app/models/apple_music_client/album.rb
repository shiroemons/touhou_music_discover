# frozen_string_literal: true

module AppleMusicClient
  LIMIT = 100

  class Album
    def self.fetch(album_id)
      return if AppleMusicAlbum.exists?(apple_music_id: album_id)

      apple_music_album = AppleMusic::Album.find(album_id)
      save_album(apple_music_album)
    end

    def self.fetch_artists_albums(artist_id)
      apple_music_albums = []
      offset = 0
      loop do
        albums = AppleMusic::Artist.get_relationship(artist_id, :albums, limit: LIMIT, offset: offset)
        apple_music_albums.push(*albums)
        break if albums.size < LIMIT

        offset += LIMIT
      end

      apple_music_albums.each do |album|
        AppleMusicAlbum.save_album(album)
      end
    rescue AppleMusic::ApiError => e
      puts artist_id
      logger.warn e
    end
  end
end
