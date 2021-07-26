# frozen_string_literal: true

module SpotifyClient
  class Artist
    def self.fetch(id)
      artist = RSpotify::Artist.find(id)
      spotify_id = artist.id
      name = artist.name
      url = artist.external_urls['spotify']
      follower_count = artist.followers['total']
      spotify_artist = SpotifyArtist.find_or_create_by!(spotify_id: spotify_id, name: name, url: url)
      spotify_artist.update!(follower_count: follower_count, payload: artist.as_json) if spotify_artist.follower_count != follower_count
    end
  end
end
