class BulkRetrieval < Avo::BaseAction
  self.name = "一括取得"
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(**args)
    # Spotify
    SpotifyClient::Album.fetch_touhou_albums

    # Apple Music
    AppleMusicTrack.fetch_tracks_and_albums

    # YouTube Music
    YtmusicAlbum.fetch_albums
    YtmusicTrack.fetch_tracks

    # LINE MUSIC
    LineMusicAlbum.fetch_albums
    LineMusicTrack.fetch_tracks

    # Set Circle
    Album.missing_circles.eager_load(:spotify_album).each do |album|
      artist_name = album&.spotify_album&.artist_name
      artist_name = artist_name&.delete_prefix('ZUN / ')
      artists = artist_name&.split(' / ')
      artists = artists&.map { Circle::SPOTIFY_ARTIST_TO_CIRCLE[_1].presence || _1 }&.flatten
      artists&.uniq&.each do |artist|
        circle = Circle.find_by(name: artist)
        album.circles.push(circle) if circle.present?
      end
      next unless album.circles.empty?

      artist = Circle::JAN_TO_CIRCLE[album.jan_code]
      circle = Circle.find_by(name: artist)
      album.circles.push(circle) if circle.present?
    end
  end
end
