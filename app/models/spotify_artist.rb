# frozen_string_literal: true

class SpotifyArtist < ApplicationRecord
  EXCLUDE_SPOTIFY_IDS = [
    '2XEx6N3gknSmtshM0PVuxu' # GUMI
  ].freeze

  def self.save_artist(s_artist)
    return nil if s_artist.blank?

    spotify_artist = SpotifyArtist.find_or_create_by!(
      spotify_id: s_artist.id,
      name: s_artist.name,
      url: s_artist.external_urls['spotify']
    )

    spotify_artist.update!(
      follower_count: s_artist.followers['total'],
      payload: s_artist.as_json
    )
    spotify_artist
  end
end
