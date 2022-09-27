# frozen_string_literal: true

class SpotifyAlbumsCount < Avo::Dashboards::MetricCard
  self.id = 'spotify_albums_count'
  self.label = 'Spotify アルバム総数'
  self.suffix = '枚'

  def query
    scope = SpotifyAlbum

    scope = scope.is_touhou if options[:is_touhou].present?

    result scope.count
  end
end
