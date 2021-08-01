# frozen_string_literal: true

class AppleMusicArtist < ApplicationRecord
  def self.save_artist(am_artist)
    apple_music_artist = AppleMusicArtist.find_or_create_by!(
      apple_music_id: am_artist.id,
      name: am_artist.name,
      url: am_artist.url
    )

    apple_music_artist.update!(payload: am_artist.as_json)
  end
end
