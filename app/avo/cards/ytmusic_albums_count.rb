# frozen_string_literal: true

class YtmusicAlbumsCount < Avo::Dashboards::MetricCard
  self.id = 'ytmusic_albums_count'
  self.label = 'YouTube Music アルバム総数'
  self.suffix = '枚'

  def query
    scope = YtmusicAlbum

    scope = scope.is_touhou if options[:is_touhou].present?

    result scope.count
  end
end
