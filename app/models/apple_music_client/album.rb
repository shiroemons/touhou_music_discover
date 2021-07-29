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
        save_album(album)
      end
    rescue AppleMusic::ApiError => e
      puts artist_id
      logger.warn e
    end

    # AppleMusicのアルバム情報を保存する
    def self.save_album(apple_music_album)
      return nil if apple_music_album.record_label != ::Album::TOUHOU_MUSIC_LABEL

      am_album = ::AppleMusicAlbum.find_or_create_by!(
        apple_music_id: apple_music_album.id,
        name: apple_music_album.name,
        label: apple_music_album.record_label,
        url: apple_music_album.url,
        release_date: apple_music_album.release_date,
        total_tracks: apple_music_album.track_count
      )
      am_album.update(payload: apple_music_album.as_json) if am_album.payload.nil?
      am_album
    end
  end
end
