# frozen_string_literal: true

module AppleMusicClient
  class Artist
    def self.fetch(ids)
      am_artists = AppleMusic::Artist.get_collection_by_ids(ids)
      am_artists.each do |am_artist|
        AppleMusicArtist.save_artist(am_artist)
      end
    end
  end
end
