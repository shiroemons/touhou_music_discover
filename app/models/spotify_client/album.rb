# frozen_string_literal: true

module SpotifyClient
  class Album
    LIMIT = 50

    def self.fetch_artists_albums_tracks(artist_id)
      return if artist_id.blank?

      artist = RSpotify::Artist.find(artist_id)

      albums = []
      album_offset = 0

      # アーティストに紐づくすべてのアルバム情報を収集する
      loop do
        # Spotifyのアルバム情報を取得
        spotify_albums = artist.albums(limit: LIMIT, offset: album_offset)

        albums.push(*spotify_albums)
        break if spotify_albums.count < LIMIT

        album_offset += LIMIT
      end

      # labelが "東方同人音楽流通"のみを絞り込む
      albums = albums.select { |album| album.label == ::Album::TOUHOU_MUSIC_LABEL }

      albums.each do |s_album|
        # アルバムの総曲数分トラックの登録がある場合、スキップする
        next if SpotifyTrack.includes(:spotify_album).where(spotify_album: { spotify_id: s_album.id }).count == s_album.total_tracks

        spotify_album = save_album(s_album)

        # アルバムの登録がない または、アルバムのトラック数が0曲 の場合はスキップする
        next if spotify_album.nil? || !spotify_album.total_tracks.positive?

        tracks = []
        track_offset = 0

        # アルバムに紐づくすべてのトラック情報を収集する
        loop do
          # Spotifyのアルバムに紐づくトラック情報を取得
          spotify_tracks = if track_offset.zero?
                             s_album.tracks_cache
                           else
                             s_album.tracks(limit: LIMIT, offset: track_offset)
                           end

          tracks.push(*spotify_tracks)
          break if spotify_tracks.count < LIMIT

          track_offset += LIMIT
        end

        tracks.each do |track|
          # すでに登録済みの場合、スキップする
          next if SpotifyTrack.exists?(spotify_id: track.id)

          save_track(spotify_album, track)
        end
      end
    end

    # Spotifyのアルバム情報を保存する
    def self.save_album(spotify_album)
      # labelが "東方同人音楽流通" 以外は nil を返す
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
        total_tracks: spotify_album.total_tracks
      )

      if spotify_album.release_date
        release_date = begin
          Date.parse(spotify_album.release_date)
        rescue StandardError
          # release_date が "年のみ" の場合がある。 "01/01"を設定する
          Date.parse("#{spotify_album.release_date}/01/01")
        end
        s_album.update!(release_date: release_date) if s_album.release_date != release_date
      end

      s_album.update!(payload: spotify_album.as_json)
      s_album
    end

    # Spotifyのトラック情報を保存する
    def self.save_track(s_album, spotify_track)
      isrc = spotify_track.external_ids['isrc']
      track = ::Track.find_or_create_by!(isrc: isrc)
      track.album_ids.push(s_album.album_id) unless track.album_ids.include?(s_album.album_id)

      s_track = ::SpotifyTrack.find_or_create_by!(
        album_id: s_album.album_id,
        track_id: track.id,
        spotify_album_id: s_album.id,
        spotify_id: spotify_track.id,
        name: spotify_track.name,
        label: s_album.label,
        url: spotify_track.external_urls['spotify'],
        release_date: s_album.release_date,
        disc_number: spotify_track.disc_number,
        track_number: spotify_track.track_number,
        duration_ms: spotify_track.duration_ms
      )
      s_track.update(payload: spotify_track.as_json)
      s_track
    end
  end
end
