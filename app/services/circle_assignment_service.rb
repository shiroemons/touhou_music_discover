# frozen_string_literal: true

class CircleAssignmentService
  STREAMING_ALBUM_ASSOCIATIONS = %i[spotify_album apple_music_album].freeze

  def assign_missing
    Album.missing_circles.includes(STREAMING_ALBUM_ASSOCIATIONS).find_each do |album|
      assign(album)
    end
  end

  def assign(album)
    circle_names_for(album).each do |circle_name|
      add_circle(album, circle_name)
    end

    add_circle(album, Circle::JAN_TO_CIRCLE[album.jan_code]) if album.circles.empty?
  end

  private

  def circle_names_for(album)
    streaming_artist_names(album)
      .flat_map { |artist_name| circle_names_from_artist_name(artist_name) }
      .uniq
  end

  def streaming_artist_names(album)
    STREAMING_ALBUM_ASSOCIATIONS.filter_map do |association|
      album.public_send(association)&.artist_name.presence
    end
  end

  def circle_names_from_artist_name(artist_name)
    artist_name
      .delete_prefix('ZUN / ')
      .split(' / ')
      .flat_map { |artist| circle_names_from_streaming_artist(artist.strip) }
      .compact_blank
  end

  def circle_names_from_streaming_artist(artist_name)
    Circle::SPOTIFY_ARTIST_TO_CIRCLE[artist_name].presence || artist_name
  end

  def add_circle(album, circle_name)
    return if circle_name.blank?

    circle = Circle.find_by(name: circle_name)
    album.circles << circle if circle.present?
  end
end
