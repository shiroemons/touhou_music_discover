# frozen_string_literal: true

class TracksCount < Avo::Dashboards::MetricCard
  self.id = 'tracks_count'
  self.label = 'Track total count'

  def query
    scope = Track

    scope = scope.is_touhou if options[:is_touhou].present?

    result scope.count
  end
end
