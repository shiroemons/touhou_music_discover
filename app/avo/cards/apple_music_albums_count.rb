# frozen_string_literal: true

class AppleMusicAlbumsCount < Avo::Dashboards::MetricCard
  self.id = 'apple_music_albums_count'
  self.label = 'AppleMusic アルバム総数'
  self.suffix = '枚'

  def query
    scope = AppleMusicAlbum

    scope = scope.is_touhou if options[:is_touhou].present?

    result scope.count
  end
end
