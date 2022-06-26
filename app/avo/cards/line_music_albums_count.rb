# frozen_string_literal: true

class LineMusicAlbumsCount < Avo::Dashboards::MetricCard
  self.id = 'line_music_albums_count'
  self.label = 'LINE MUSIC album total count'

  def query
    scope = LineMusicAlbum

    scope = scope.is_touhou if options[:is_touhou].present?

    result scope.count
  end
end
