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
        tracks = AppleMusic::Album.get_relationship(album_id, :tracks, limit: LIMIT, offset: offset)
        am_tracks.push(*tracks)
        break if tracks.size < LIMIT

        offset += LIMIT
      end
      am_tracks
    end
  end
end
