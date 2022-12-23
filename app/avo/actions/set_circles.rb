# frozen_string_literal: true

class SetCircles < Avo::BaseAction
  self.name = 'Set circles'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    Album.missing_circles.eager_load(:spotify_album).each do |album|
      artist_name = album&.spotify_album&.artist_name
      artist_name = artist_name&.sub(%r{\AZUN / }, '')
      artists = artist_name&.split(' / ')
      artists = artists&.map { Circle::SPOTIFY_ARTIST_TO_CIRCLE[_1].presence || _1 }&.flatten
      artists&.uniq&.each do |artist|
        circle = Circle.find_by(name: artist)
        album.circles.push(circle) if circle.present?
      end
      next unless album.circles.size.zero?

      artist = Circle::JAN_TO_CIRCLE[album.jan_code]
      circle = Circle.find_by(name: artist)
      album.circles.push(circle) if circle.present?
    end
    succeed 'Done!'
    reload
  end
end
