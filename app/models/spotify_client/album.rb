# frozen_string_literal: true

module SpotifyClient
  class Album
    LIMIT = 50

    def self.fetch(artist_ids)
      return nil if artist_ids.blank?

      s_artists = RSpotify::Artist.find(artist_ids)
      s_artists&.each do |s_artist|
        # 特定のアーティストのみ収集する SpotifyのアーティストIDを指定する
        # next unless s_artist.id == ''
        next if s_artist.id == '6wH1UiZO1V6f7rZ7b0mlci' # 洛天依

        Retryable.retryable(tries: 5, sleep: 15, on: [RestClient::TooManyRequests, RestClient::InternalServerError]) do |retries, exception|
          print "-> try #{retries} failed with exception: #{exception}" if retries.positive?
          fetch_process(s_artist) if ::SpotifyArtist::EXCLUDE_SPOTIFY_IDS.exclude?(s_artist.id)
        end
      end
    end

    def self.fetch_process(s_artist)
      print "\e[H\e[2J"
      print "#{s_artist.id}: #{s_artist.name} 開始"
      s_albums = fetch_albums(s_artist)
      s_albums.each do |s_album|
        next if SpotifyTrack.album_spotify_id(s_album.id).count == s_album.total_tracks

        spotify_album = SpotifyAlbum.save_album(s_album)
        s_tracks = fetch_tracks(s_album)
        s_tracks.each do |s_track|
          SpotifyTrack.save_track(spotify_album, s_track)
          sleep 0.1
        end
      end
      print '->完了'
    end

    def self.fetch_albums(s_artist)
      s_albums = []
      album_offset = 0
      loop do
        albums = s_artist.albums(limit: LIMIT, offset: album_offset)
        s_albums.push(*albums)
        break if albums.count < LIMIT

        album_offset += LIMIT
      end
      # labelが "東方同人音楽流通"のみを絞り込む
      s_albums.select! { _1.label == ::Album::TOUHOU_MUSIC_LABEL }
      s_albums
    end

    def self.fetch_tracks(s_album)
      s_tracks = []
      track_offset = 0
      loop do
        tracks = if track_offset.zero?
                   s_album.tracks_cache
                 else
                   s_album.tracks(limit: LIMIT, offset: track_offset)
                 end
        s_tracks.push(*tracks)
        break if tracks.count < LIMIT

        track_offset += LIMIT
      end
      s_tracks
    end

    def self.update_albums(spotify_albums)
      s_albums = RSpotify::Album.find(spotify_albums.map(&:spotify_id))
      s_albums.each do |s_album|
        spotify_album = spotify_albums.find{_1.spotify_id == s_album.id}
        spotify_album&.update(payload: s_album.as_json)
      end
    end
  end
end
