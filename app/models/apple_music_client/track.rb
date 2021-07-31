# frozen_string_literal: true

module AppleMusicClient
  class Track
    LIMIT = 100

    def self.fetch_album_tracks(album)
      return if AppleMusicTrack.where(apple_music_album_id: album.id).count == album.total_tracks

      apple_music_tracks = []
      offset = 0
      loop do
        tracks = AppleMusic::Album.get_relationship(album.apple_music_id, :tracks, limit: LIMIT, offset: offset)
        apple_music_tracks.push(*tracks)
        break if tracks.size < LIMIT

        offset += LIMIT
      end

      apple_music_tracks.each do |track|
        save_apple_music_track(album, track)
      end
    end

    def self.save_apple_music_track(apple_music_album, apple_music_track)
      isrc = apple_music_track.isrc
      track = ::Track.find_or_create_by!(isrc: isrc)

      am_track = ::AppleMusicTrack.find_or_create_by!(
        track_id: track.id,
        apple_music_album_id: apple_music_album.id,
        apple_music_id: apple_music_track.id,
        name: apple_music_track.name,
        label: apple_music_album.label,
        artist_name: apple_music_track.artist_name,
        composer_name: apple_music_track.composer_name.to_s,
        url: apple_music_track.url,
        release_date: apple_music_track.release_date,
        disc_number: apple_music_track.disc_number,
        track_number: apple_music_track.track_number,
        duration_ms: apple_music_track.duration_in_millis
      )
      am_track.update(album_id: apple_music_album.album_id) if am_track.album_id.nil? && apple_music_album.album_id
      am_track.update(payload: apple_music_track.as_json) if am_track.payload.nil?
      am_track
    end
  end
end
