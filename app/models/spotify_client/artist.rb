# frozen_string_literal: true

module SpotifyClient
  class Artist
    def self.fetch(id)
      s_artist = RSpotify::Artist.find(id)
      SpotifyArtist.save_artist(s_artist)
    end
  end
end
