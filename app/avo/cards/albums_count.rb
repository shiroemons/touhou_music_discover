# frozen_string_literal: true

class AlbumsCount < Avo::Dashboards::MetricCard
  self.id = 'albums_count'
  self.label = 'アルバム総数'
  self.suffix = '枚'

  def query
    scope = Album

    scope = scope.is_touhou if options[:is_touhou].present?

    result scope.count
  end
end
