# frozen_string_literal: true

module SpotifyClient
  class Album
    LIMIT = 50

    def self.fetch_artists_albums_tracks(artist_id)
      return if artist_id.blank?

      s_artist = RSpotify::Artist.find(artist_id)

      s_albums = []
      album_offset = 0

      # アーティストに紐づくすべてのアルバム情報を収集する
      loop do
        # Spotifyのアルバム情報を取得
        albums = s_artist.albums(limit: LIMIT, offset: album_offset)

        s_albums.push(*albums)
        break if albums.count < LIMIT

        album_offset += LIMIT
      end

      # labelが "東方同人音楽流通"のみを絞り込む
      s_albums = s_albums.select { |s_album| s_album.label == ::Album::TOUHOU_MUSIC_LABEL }

      s_albums.each do |s_album|
        # アルバムの総曲数分トラックの登録がある場合、スキップする
        next if SpotifyTrack.includes(:spotify_album).where(spotify_album: { spotify_id: s_album.id }).count == s_album.total_tracks

        spotify_album = SpotifyAlbum.save_album(s_album)

        # アルバムの登録がない または、アルバムのトラック数が0曲 の場合はスキップする
        next if spotify_album.nil? || !spotify_album.total_tracks.positive?

        s_tracks = []
        track_offset = 0

        # アルバムに紐づくすべてのトラック情報を収集する
        loop do
          # Spotifyのアルバムに紐づくトラック情報を取得
          tracks = if track_offset.zero?
                     s_album.tracks_cache
                   else
                     s_album.tracks(limit: LIMIT, offset: track_offset)
                   end

          s_tracks.push(*tracks)
          break if tracks.count < LIMIT

          track_offset += LIMIT
        end

        s_tracks.each do |s_track|
          # すでに登録済みの場合、スキップする
          next if SpotifyTrack.exists?(spotify_id: s_track.id)

          SpotifyTrack.save_track(spotify_album, s_track)
        end
      end
    end
  end
end
