# frozen_string_literal: true

module AppleMusicClient
  class Artist
    def self.fetch_from_albums
      ids = AppleMusicAlbum.unscoped.pluck(:payload).flat_map do |payload|
        Array(payload&.dig('relationships', 'artists', 'data')).filter_map { |artist| artist['id'].presence }
      end.uniq
      missing_ids = ids - AppleMusicArtist.pluck(:apple_music_id)
      missing_ids.each_slice(25) { |batch| fetch(batch) }
    end

    def self.fetch(ids)
      am_artists = AppleMusic::Artist.get_collection_by_ids(ids)
      am_artists.each do |am_artist|
        AppleMusicArtist.save_artist(am_artist)
      end
    end
  end
end
