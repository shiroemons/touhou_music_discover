# frozen_string_literal: true

module SpotifyClient
  class Album
    LIMIT = 50

    def self.fetch_artists_albums_tracks(artist_id)
      return if artist_id.blank?

      artist = RSpotify::Artist.find(artist_id)
      album_offset = 0
      loop do
        # Spotifyのアルバム情報を取得
        spotify_albums = artist.albums(limit: LIMIT, offset: album_offset)
        spotify_albums.each do |s_album|
          spotify_album = save_album(s_album)

          next unless spotify_album&.total_tracks&.positive?

          track_offset = 0
          loop do
            # Spotifyのアルバムに紐づくトラック情報を取得
            spotify_tracks = if track_offset.zero?
                               s_album.tracks_cache
                             else
                               s_album.tracks(limit: LIMIT, offset: track_offset)
                             end

            spotify_tracks.each do |track|
              save_track(spotify_album, track)
              # 429 Too Many Requests対策
              sleep 0.1
            end
            track_offset += LIMIT
            break if spotify_tracks.count < LIMIT
          end
        end
        album_offset += LIMIT
        break if spotify_albums.count < LIMIT

        # 429 Too Many Requests対策
        sleep 1.0
      end
    end

    # Spotifyのアルバム情報を保存する
    def self.save_album(spotify_album)
      return nil if spotify_album.label != ::Album::TOUHOU_MUSIC_LABEL

      jan_code = spotify_album.external_ids['upc']
      album = ::Album.find_or_create_by!(jan_code: jan_code)

      s_album = ::SpotifyAlbum.find_or_create_by!(
        album_id: album.id,
        spotify_id: spotify_album.id,
        album_type: spotify_album.album_type,
        name: spotify_album.name,
        label: spotify_album.label,
        url: spotify_album.external_urls['spotify'],
        release_date: spotify_album.release_date,
        total_tracks: spotify_album.total_tracks
      )
      s_album.update(payload: spotify_album.as_json) if s_album.nil?
      s_album
    end

    # Spotifyのトラック情報を保存する
    def self.save_track(spotify_album, spotify_track)
      isrc = spotify_track.external_ids['isrc']
      track = ::Track.find_or_create_by!(isrc: isrc)

      s_track = ::SpotifyTrack.find_or_create_by!(
        album_id: spotify_album.album_id,
        track_id: track.id,
        spotify_album_id: spotify_album.id,
        spotify_id: spotify_track.id,
        name: spotify_track.name,
        label: spotify_album.label,
        url: spotify_track.external_urls['spotify'],
        release_date: spotify_album.release_date,
        disc_number: spotify_track.disc_number,
        track_number: spotify_track.track_number,
        duration_ms: spotify_track.duration_ms
      )
      s_track.update(payload: spotify_track.as_json) if s_track.payload.nil?
      s_track
    end
  end
end
