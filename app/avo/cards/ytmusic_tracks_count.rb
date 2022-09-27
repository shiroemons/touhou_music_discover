# frozen_string_literal: true

class YtmusicTracksCount < Avo::Dashboards::MetricCard
  self.id = 'ytmusic_tracks_count'
  self.label = 'YouTube Music トラック総曲数'
  self.suffix = '曲'

  def query
    scope = YtmusicTrack

    scope = scope.is_touhou if options[:is_touhou].present?

    result scope.count
  end
end
