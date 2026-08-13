# frozen_string_literal: true

module CatalogSnapshot
  class RowBuilder
    SERVICE_DEFINITIONS = CatalogSnapshot::SERVICE_DEFINITIONS
    SERVICE_PRIORITY = SERVICE_DEFINITIONS.keys.freeze

    def initialize(catalog)
      @catalog = catalog
      @albums_by_id = catalog.albums.index_by(&:id)
      @albums_by_jan = catalog.albums.index_by(&:jan_code)
    end

    def rows
      {
        'albums.jsonl' => album_rows,
        'tracks.jsonl' => track_rows,
        'circles.jsonl' => circle_rows,
        'originals.jsonl' => original_rows,
        'original_songs.jsonl' => original_song_rows,
        'circle_albums.jsonl' => circle_album_rows,
        'track_original_songs.jsonl' => track_original_song_rows,
        'service_albums.jsonl' => service_album_rows,
        'service_tracks.jsonl' => service_track_rows,
        'aliases.jsonl' => alias_rows
      }
    end

    private

    def album_rows
      @catalog.albums.sort_by(&:id).map do |album|
        title_resolution = @catalog.title_resolutions.fetch(album.id)
        release_resolution = @catalog.release_resolutions.fetch(album.id)
        ytmusic_records = @catalog.service_albums.fetch(:ytmusic).select { |record| record.album_id == album.id }
        distribution_record = ytmusic_records.min_by { |record| record.id.to_s }

        {
          id: album.id.to_s,
          jan_code: album.jan_code,
          is_touhou: album.is_touhou,
          display_name: title_resolution.display_album_name,
          release_date: release_resolution.release_date&.iso8601,
          release_year: release_resolution.release_year,
          estimated_distribution_date: distribution_record&.distributed_on&.iso8601,
          image_url: image_url_for(album.id),
          service_availability: service_availability_for_album(album.id),
          distribution_audit: distribution_audit_for(distribution_record),
          release_date_audit: {
            source: release_resolution.source,
            candidates: release_resolution.candidates.map do |candidate|
              candidate.merge(date: candidate.fetch(:date).iso8601)
            end
          }
        }
      end
    end

    def track_rows
      @catalog.tracks.sort_by { |track| [track.jan_code.to_s, position_sort_key(track), track.id.to_s] }.map do |track|
        album = @albums_by_jan.fetch(track.jan_code)
        resolution = @catalog.title_resolutions.fetch(album.id)

        {
          id: track.id.to_s,
          album_id: album.id.to_s,
          isrc: track.isrc,
          is_touhou: track.is_touhou,
          display_name: resolution.display_track_name(track),
          disc_number: position_for_track(track).first,
          track_number: position_for_track(track).last,
          image_url: image_url_for_track(track),
          service_availability: service_availability_for_track(track)
        }
      end
    end

    def circle_rows
      @catalog.circles.sort_by(&:id).map { |circle| { id: circle.id.to_s, name: circle.name } }
    end

    def original_rows
      @catalog.originals.sort_by(&:code).map do |original|
        {
          code: original.code,
          type: original.original_type,
          title: original.title,
          short_title: original.short_title,
          series_order: original.series_order
        }
      end
    end

    def original_song_rows
      @catalog.original_songs.sort_by(&:code).map do |original_song|
        {
          code: original_song.code,
          original_code: original_song.original_code,
          title: original_song.title,
          composer: original_song.composer,
          track_number: original_song.track_number,
          is_duplicate: original_song.is_duplicate
        }
      end
    end

    def circle_album_rows
      @catalog.circle_albums.sort_by(&:id).map do |relation|
        { id: relation.id.to_s, circle_id: relation.circle_id.to_s, album_id: relation.album_id.to_s }
      end
    end

    def track_original_song_rows
      @catalog.track_original_songs.sort_by(&:id).map do |relation|
        { id: relation.id.to_s, track_id: relation.track_id.to_s, original_song_code: relation.original_song_code }
      end
    end

    def service_album_rows
      SERVICE_PRIORITY.flat_map do |service|
        definition = SERVICE_DEFINITIONS.fetch(service)
        @catalog.service_albums.fetch(service).sort_by(&:id).map do |record|
          {
            source_record_id: record.id.to_s,
            album_id: record.album_id.to_s,
            service: definition.fetch(:service),
            name: record.name,
            url: record.url,
            release_date: record.respond_to?(:release_date) ? record.release_date&.iso8601 : nil,
            release_year: release_year_for(record),
            total_tracks: record.respond_to?(:total_tracks) ? record.total_tracks : nil,
            image_url: record.image_url,
            availability: service_album_availability(record)
          }
        end
      end
    end

    def service_track_rows
      SERVICE_PRIORITY.flat_map do |service|
        definition = SERVICE_DEFINITIONS.fetch(service)
        @catalog.service_tracks.fetch(service).sort_by(&:id).map do |record|
          {
            source_record_id: record.id.to_s,
            album_id: record.album_id&.to_s,
            track_id: record.track_id&.to_s,
            service_album_record_id: record.public_send(definition.fetch(:provider_album_fk))&.to_s,
            service: definition.fetch(:service),
            name: record.name,
            url: record.url,
            disc_number: record.respond_to?(:disc_number) ? record.disc_number : nil,
            track_number: record.respond_to?(:track_number) ? record.track_number : nil,
            duration_ms: record.respond_to?(:duration_ms) ? record.duration_ms : nil,
            availability: record.url.present? ? 'available' : 'unknown'
          }
        end
      end
    end

    def alias_rows
      aliases = []
      @catalog.albums.each do |album|
        add_alias(aliases, 'album', album.id, album.jan_code, 'jan_code')
        resolution = @catalog.title_resolutions.fetch(album.id)
        add_alias(aliases, 'album', album.id, resolution.display_album_name, 'canonical')
        SERVICE_PRIORITY.each do |service|
          @catalog.service_albums.fetch(service).select { |record| record.album_id == album.id }.each do |record|
            add_alias(aliases, 'album', album.id, record.name, SERVICE_DEFINITIONS.fetch(service).fetch(:service))
          end
        end
      end

      @catalog.tracks.each do |track|
        add_alias(aliases, 'track', track.id, track.isrc, 'isrc')
        album = @catalog.albums.find { |candidate| candidate.jan_code == track.jan_code }
        add_alias(aliases, 'track', track.id, @catalog.title_resolutions.fetch(album.id).display_track_name(track), 'canonical')
        SERVICE_PRIORITY.each do |service|
          definition = SERVICE_DEFINITIONS.fetch(service)
          @catalog.service_tracks.fetch(service).select { |record| record.track_id == track.id }.each do |record|
            add_alias(aliases, 'track', track.id, record.name, definition.fetch(:service))
          end
        end
      end

      @catalog.circles.each { |circle| add_alias(aliases, 'circle', circle.id, circle.name, 'canonical') }
      @catalog.originals.each do |original|
        add_alias(aliases, 'original', original.code, original.title, 'canonical')
        add_alias(aliases, 'original', original.code, original.short_title, 'canonical')
      end
      @catalog.original_songs.each { |song| add_alias(aliases, 'original_song', song.code, song.title, 'canonical') }

      aliases.sort_by { |row| [row[:entity_type], row[:entity_id].to_s, row[:value], row[:source]] }
    end

    def add_alias(aliases, entity_type, entity_id, value, source)
      normalized = AlbumTitleNormalizer.normalize(value)
      return if normalized.blank?
      return if aliases.any? { |row| row[:entity_type] == entity_type && row[:entity_id].to_s == entity_id.to_s && row[:value] == normalized }

      aliases << { entity_type:, entity_id: entity_id.to_s, value: normalized, source: }
    end

    def position_for_track(track)
      positions = SERVICE_PRIORITY.flat_map do |service|
        @catalog.service_tracks.fetch(service).select { |record| record.track_id == track.id }.filter_map do |record|
          next if record.respond_to?(:disc_number) && record.disc_number.blank? && record.track_number.blank?

          [record.respond_to?(:disc_number) ? record.disc_number : nil, record.respond_to?(:track_number) ? record.track_number : nil, record.id.to_s]
        end
      end
      selected = positions.min_by { |disc, number, id| [disc || 99_999, number || 99_999, id] }
      [selected&.first, selected&.second]
    end

    def position_sort_key(track)
      disc_number, track_number = position_for_track(track)
      [disc_number || 99_999, track_number || 99_999]
    end

    def image_url_for(album_id)
      SERVICE_PRIORITY.filter_map do |service|
        @catalog.service_albums.fetch(service).select { |record| record.album_id == album_id }.sort_by(&:id).filter_map(&:image_url)
      end.flatten.first
    end

    def image_url_for_track(track)
      SERVICE_PRIORITY.filter_map do |service|
        definition = SERVICE_DEFINITIONS.fetch(service)
        @catalog.service_tracks.fetch(service).select { |record| record.track_id == track.id }.sort_by(&:id).filter_map do |record|
          album_id = record.public_send(definition.fetch(:provider_album_fk))
          @catalog.service_albums.fetch(service).find { |album| album.id == album_id }&.image_url
        end
      end.flatten.first
    end

    def service_availability_for_album(album_id)
      SERVICE_PRIORITY.to_h do |service|
        expected_ids = @catalog.expected_track_ids_by_jan.fetch(@catalog.albums.find { |album| album.id == album_id }.jan_code, Set.new)
        observed_ids = @catalog.service_tracks.fetch(service).select { |record| record.album_id == album_id }.to_set(&:track_id)
        status = if @catalog.service_albums.fetch(service).none? { |record| record.album_id == album_id }
                   'unavailable'
                 elsif expected_ids.empty? || (expected_ids - observed_ids).empty?
                   'available'
                 elsif observed_ids.empty?
                   'unknown'
                 else
                   'partial'
                 end
        [SERVICE_DEFINITIONS.fetch(service).fetch(:service), status]
      end
    end

    def service_availability_for_track(track)
      SERVICE_PRIORITY.to_h do |service|
        status = @catalog.service_tracks.fetch(service).any? { |record| record.track_id == track.id } ? 'available' : 'unavailable'
        [SERVICE_DEFINITIONS.fetch(service).fetch(:service), status]
      end
    end

    def service_album_availability(record)
      definition = SERVICE_DEFINITIONS.fetch(SERVICE_PRIORITY.find { |service| @catalog.service_albums.fetch(service).include?(record) })
      tracks = @catalog.service_tracks.fetch(SERVICE_PRIORITY.find { |service| @catalog.service_albums.fetch(service).include?(record) }).select do |track|
        track.public_send(definition.fetch(:provider_album_fk)) == record.id
      end
      expected_ids = @catalog.expected_track_ids_by_jan.fetch(@albums_by_id.fetch(record.album_id).jan_code, Set.new)
      observed_ids = tracks.to_set(&:track_id)
      return 'available' if expected_ids.empty? || (expected_ids - observed_ids).empty?
      return 'unknown' if observed_ids.empty?

      'partial'
    end

    def distribution_audit_for(record)
      return nil unless record

      stats = record.distribution_stats.is_a?(Hash) ? record.distribution_stats : {}
      {
        source_record_id: record.id.to_s,
        source: record.distribution_source,
        algorithm_version: stats['algorithm_version'],
        latest_status: stats['latest_status'] || record.distribution_source,
        fetched_at: record.distribution_fetched_at&.iso8601,
        last_successful_at: stats['last_successful_at'],
        last_successful_source: stats['last_successful_source'],
        correction: stats['correction']
      }
    end

    def release_year_for(record)
      return record.release_date.year if record.respond_to?(:release_date) && record.release_date.present?
      return unless record.respond_to?(:release_year)

      year = record.release_year.to_s
      year.to_i if year.match?(/\A\d{4}\z/)
    end
  end
end
