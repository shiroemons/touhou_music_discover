# frozen_string_literal: true

module SpotifyClient
  class Artist
    def self.fetch(ids)
      s_artists = RSpotify::Artist.find(ids)
      s_artists.each do |s_artist|
        SpotifyArtist.save_artist(s_artist)
      end
    end
  end
end
