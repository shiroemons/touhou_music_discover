# frozen_string_literal: true

module AppleMusicClient
  class Artist
    def self.fetch(id)
      puts id
      artist = AppleMusic::Artist.find(id)
      save_apple_music_artist(artist)
    end

    def self.save_apple_music_artist(artist)
      apple_music_artist = AppleMusicArtist.find_or_create_by!(
        apple_music_id: artist.id,
        name: artist.name,
        url: artist.url
      )

      apple_music_artist.update!(payload: artist.as_json) if apple_music_artist.payload.nil?
    end
  end
end
