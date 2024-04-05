# frozen_string_literal: true

module SpotifyClient
  class Album
    LIMIT = 50
    KEYWORD = 'label:東方同人音楽流通'

    def self.fetch_touhou_albums
      Parallel.each((2000..Time.zone.today.year), in_processes: 7) do |year|
        keyword = "#{KEYWORD} year:#{year}"
        search_and_save_albums(keyword, year)
      end
    end

    def self.search_and_save_albums(keyword, year)
      offset = 0
      loop do
        s_albums = RSpotify::Album.search(keyword, limit: LIMIT, offset:, market: 'JP')
        s_albums.each do |s_album|
          process_album(s_album)
        end
        offset += s_albums.size
        break if s_albums.size < LIMIT

        puts "year:#{year}\toffset: #{offset}"
      end
    end

    def self.process_album(s_album)
      spotify_album = SpotifyAlbum.exists?(spotify_id: s_album.id) ? SpotifyAlbum.find_by(spotify_id: s_album.id) : SpotifyAlbum.save_album(s_album)
      return if spotify_album.nil? || spotify_album.total_tracks == spotify_album.spotify_tracks.count

      s_tracks = s_album.tracks
      save_tracks(spotify_album, s_tracks)
    end

    def self.save_tracks(spotify_album, s_tracks)
      s_tracks.each do |s_track|
        SpotifyTrack.save_track(spotify_album, s_track)
      end
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
        spotify_album = spotify_albums.find { _1.spotify_id == s_album.id }
        spotify_album&.update(
          album_type: s_album.album_type,
          name: s_album.name,
          url: s_album.external_urls['spotify'],
          total_tracks: s_album.total_tracks,
          payload: s_album.as_json
        )
      end
    end
  end
end
