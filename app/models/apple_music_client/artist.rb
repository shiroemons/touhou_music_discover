# frozen_string_literal: true

module AppleMusicClient
  class Artist
    def self.fetch(id)
      artist = AppleMusic::Artist.find(id)
      AppleMusicArtist.save_artist(artist)
    end
  end
end
