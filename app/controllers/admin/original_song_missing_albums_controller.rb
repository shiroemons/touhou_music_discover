# frozen_string_literal: true

module Admin
  class OriginalSongMissingAlbumsController < BaseController
    before_action :authenticate_admin_if_configured

    def index
      @album_resource = Admin::Resource.find!('albums')
      @query = params.fetch(:q, '').to_s.strip
      @pagy, @albums = pagy(:offset, album_scope, limit: Admin::Resource::DEFAULT_ITEMS)
      @missing_track_counts = missing_track_counts(@albums)
      @copy_text = copy_text_for(copy_scope)
    end

    private

    def album_scope
      search_albums(base_scope, @query).order(jan_code: :desc)
    end

    def copy_scope
      search_albums(base_scope, @query).order(jan_code: :desc)
    end

    def base_scope
      Album
        .tracks_missing_original_songs
        .includes(:circles, :spotify_album, :apple_music_album, :ytmusic_album, :line_music_album)
        .distinct
    end

    def search_albums(scope, query)
      return scope if query.blank?

      pattern = "%#{Album.sanitize_sql_like(query)}%"
      scope.left_joins(:circles, :spotify_album, :apple_music_album, :ytmusic_album, :line_music_album).where(
        <<~SQL.squish,
          albums.jan_code ILIKE :query OR
          circles.name ILIKE :query OR
          spotify_albums.name ILIKE :query OR
          apple_music_albums.name ILIKE :query OR
          ytmusic_albums.name ILIKE :query OR
          line_music_albums.name ILIKE :query
        SQL
        query: pattern
      ).distinct
    end

    def missing_track_counts(albums)
      Track
        .missing_original_songs
        .where(jan_code: albums.map(&:jan_code))
        .group(:jan_code)
        .count
    end

    def copy_text_for(scope)
      scope.map { |album| [album.circle_name, album_name(album)].join("\t") }.join("\n")
    end

    def album_name(album)
      album.spotify_album_name || album.apple_music_album_name || album.ytmusic_album_name || album.line_music_album_name || album.jan_code
    end
    helper_method :album_name
  end
end
