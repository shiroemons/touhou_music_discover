# frozen_string_literal: true

class LineMusicTracksCount < Avo::Dashboards::MetricCard
  self.id = 'line_music_tracks_count'
  self.label = 'LINE MUSIC トラック総曲数'
  self.suffix = '曲'

  def query
    scope = LineMusicTrack

    scope = scope.is_touhou if options[:is_touhou].present?

    result scope.count
  end
end
