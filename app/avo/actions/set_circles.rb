# frozen_string_literal: true

class SetCircles < Avo::BaseAction
  self.name = 'サークルを設定'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    Album.missing_circles.eager_load(:spotify_album).each do |album|
      artist_name = album&.spotify_album&.artist_name
      artist_name = artist_name&.delete_prefix('ZUN / ')
      artists = artist_name&.split(' / ')
      artists = artists&.map { Circle::SPOTIFY_ARTIST_TO_CIRCLE[it].presence || it }&.flatten
      artists&.uniq&.each do |artist|
        circle = Circle.find_by(name: artist)
        album.circles.push(circle) if circle.present?
      end
      next unless album.circles.empty?

      artist = Circle::JAN_TO_CIRCLE[album.jan_code]
      circle = Circle.find_by(name: artist)
      album.circles.push(circle) if circle.present?
    end
    succeed 'Done!'
    reload
  end
end
