# frozen_string_literal: true

module AppleMusicClient
  class Track
    LIMIT = 100

    def self.fetch_album_tracks(apple_music_album)
      return if AppleMusicTrack.where(apple_music_album_id: apple_music_album.id).count == apple_music_album.total_tracks

      am_tracks = fetch_tracks(apple_music_album.apple_music_id)
      am_tracks.each do |am_track|
        AppleMusicTrack.save_track(apple_music_album, am_track)
      end
    end

    def self.fetch_tracks(album_id)
      am_tracks = []
      offset = 0
      loop do
        tracks = AppleMusic::Album.get_relationship(album_id, :tracks, limit: LIMIT, offset:)
        am_tracks.push(*tracks)
        break if tracks.size < LIMIT

        offset += LIMIT
      end
      am_tracks
    end

    def self.fetch_tracks_by_isrc(isrc)
      am_tracks = AppleMusic::Song.get_collection_by_isrc(isrc)
      am_tracks.each do |am_track|
        am_track.albums.each do |am_album|
          apple_music_album = AppleMusicClient::Album.fetch(am_album.id)
          AppleMusicClient::Track.fetch_album_tracks(apple_music_album) if apple_music_album
        end
      end
    end

    def self.update_tracks(apple_music_tracks)
      ids = apple_music_tracks.map(&:apple_music_id)
      am_tracks = AppleMusic::Song.get_collection_by_ids(ids)
      am_tracks.each do |am_track|
        apple_music_track = apple_music_tracks.find{_1.apple_music_id == am_track.id}
        apple_music_track&.update(name: am_track.name)
        apple_music_track&.update(payload: am_track.as_json)
      end
    end
  end
end
