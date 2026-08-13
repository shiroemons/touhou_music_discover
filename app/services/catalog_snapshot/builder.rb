# frozen_string_literal: true

module CatalogSnapshot
  class Builder
    def build
      albums = Album.unscoped.where(is_touhou: true).order(:id).to_a
      album_ids = albums.map(&:id)
      jan_codes = albums.map(&:jan_code)

      tracks = if jan_codes.empty?
                 []
               else
                 Track.unscoped.where(jan_code: jan_codes).order(:id).to_a
               end
      track_ids = tracks.map(&:id)

      circle_albums = CirclesAlbum.unscoped.where(album_id: album_ids).order(:id).to_a
      circles = load_records(Circle, circle_albums.map(&:circle_id))

      track_original_songs = TracksOriginalSong.unscoped.where(track_id: track_ids).order(:id).to_a
      original_songs = load_records(OriginalSong, track_original_songs.map(&:original_song_code))
      originals = load_records(Original, original_songs.map(&:original_code))

      service_records = load_service_records(album_ids:)
      title_resolutions = AlbumTitleResolver.for_many(albums)
      release_resolutions = albums.to_h do |album|
        service_albums = CatalogSnapshot::SERVICE_DEFINITIONS.keys.index_with do |service|
          service_records.fetch(service).fetch(:albums).select { |record| record.album_id == album.id }
        end
        [album.id, ReleaseDateResolver.new(service_albums).resolve]
      end

      Catalog.new(
        albums:,
        tracks:,
        circles:,
        originals:,
        original_songs:,
        circle_albums:,
        track_original_songs:,
        service_albums: service_records.transform_values { |records| records.fetch(:albums) },
        service_tracks: service_records.transform_values { |records| records.fetch(:tracks) },
        title_resolutions:,
        release_resolutions:,
        expected_track_ids_by_jan: tracks.group_by(&:jan_code).transform_values { |rows| rows.to_set(&:id) }
      )
    end

    private

    def load_records(model, ids)
      return [] if ids.empty?

      primary_key = model.primary_key
      model.unscoped.where(primary_key => ids.uniq).order(primary_key).to_a
    end

    def load_service_records(album_ids:)
      CatalogSnapshot::SERVICE_DEFINITIONS.to_h do |service, definition|
        album_model = definition.fetch(:album_class_name).constantize
        track_model = definition.fetch(:track_class_name).constantize

        albums = album_model.unscoped.where(album_id: album_ids).then do |scope|
          definition.fetch(:active) ? scope.where(active: true) : scope
        end.order(:id).to_a
        provider_album_ids = albums.map(&:id)

        tracks = if provider_album_ids.empty?
                   []
                 else
                   track_model.unscoped
                              .where(definition.fetch(:provider_album_fk) => provider_album_ids)
                              .order(:id)
                              .to_a
                 end

        [service, { albums:, tracks: }]
      end
    end
  end
end
