# frozen_string_literal: true

class LineMusicAlbumsCount < Avo::Dashboards::MetricCard
  self.id = 'line_music_albums_count'
  self.label = 'LINE MUSIC アルバム総数'
  self.suffix = '枚'

  def query
    scope = LineMusicAlbum

    scope = scope.is_touhou if options[:is_touhou].present?

    result scope.count
  end
end
