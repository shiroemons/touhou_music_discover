# frozen_string_literal: true

class AppleMusicTracksCount < Avo::Dashboards::MetricCard
  self.id = 'apple_music_tracks_count'
  self.label = 'AppleMusic track total count'

  def query
    scope = AppleMusicTrack

    scope = scope.is_touhou if options[:is_touhou].present?

    result scope.count
  end
end
