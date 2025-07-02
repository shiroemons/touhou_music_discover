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
        next unless am_track.albums&.dig('data')

        am_track.albums['data'].each do |am_album|
          apple_music_album = AppleMusicClient::Album.fetch(am_album['id'])
          AppleMusicClient::Track.fetch_album_tracks(apple_music_album) if apple_music_album
        end
      end
    end

    def self.update_tracks(apple_music_tracks)
      ids = apple_music_tracks.map(&:apple_music_id)
      am_tracks = AppleMusic::Song.get_collection_by_ids(ids)
      am_tracks.each do |am_track|
        apple_music_track = apple_music_tracks.find { it.apple_music_id == am_track.id }
        apple_music_track&.update(
          name: am_track.name,
          artist_name: am_track.artist_name,
          composer_name: am_track.composer_name.to_s,
          url: am_track.url,
          disc_number: am_track.disc_number,
          track_number: am_track.track_number,
          duration_ms: am_track.duration_in_millis,
          payload: am_track.as_json
        )
      end
    end
  end
end
