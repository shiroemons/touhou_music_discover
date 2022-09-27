# frozen_string_literal: true

class SpotifyTracksCount < Avo::Dashboards::MetricCard
  self.id = 'spotify_tracks_count'
  self.label = 'Spotify トラック総曲数'
  self.suffix = '曲'

  def query
    scope = SpotifyTrack

    scope = scope.is_touhou if options[:is_touhou].present?

    result scope.count
  end
end
