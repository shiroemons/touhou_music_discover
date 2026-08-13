# frozen_string_literal: true

module CatalogSnapshot
  class QualityGate
    SERVICE_DEFINITIONS = CatalogSnapshot::SERVICE_DEFINITIONS

    def initialize(catalog)
      @catalog = catalog
      @report = QualityReport.new
      @album_by_id = catalog.albums.index_by(&:id)
      @track_by_id = catalog.tracks.index_by(&:id)
      @circle_by_id = catalog.circles.index_by(&:id)
      @original_by_code = catalog.originals.index_by(&:code)
      @original_song_by_code = catalog.original_songs.index_by(&:code)
      @service_album_by_id = {}
    end

    def call
      validate_canonical_records
      validate_relations
      validate_service_records
      add_warnings
      @report
    end

    private

    def validate_canonical_records
      validate_unique_ids(@catalog.albums, :id, :duplicate_album_id)
      validate_unique_values(@catalog.albums, :jan_code, :duplicate_jan_code)
      validate_unique_ids(@catalog.tracks, :id, :duplicate_track_id)
      validate_unique_ids(@catalog.circles, :id, :duplicate_circle_id)
      validate_unique_values(@catalog.originals, :code, :duplicate_original_code)
      validate_unique_values(@catalog.original_songs, :code, :duplicate_original_song_code)

      @catalog.albums.each do |album|
        @report.add_error(:missing_album_id, 'Album ID is blank', jan_code: album.jan_code) if album.id.blank?
        @report.add_error(:missing_jan_code, 'Album JAN code is blank', album_id: album.id) if album.jan_code.blank?
      end

      @catalog.tracks.each do |track|
        @report.add_error(:missing_track_id, 'Track ID is blank', isrc: track.isrc) if track.id.blank?
        @report.add_error(:missing_track_isrc, 'Track ISRC is blank', track_id: track.id) if track.isrc.blank?
        next if @catalog.expected_track_ids_by_jan.fetch(track.jan_code, Set.new).include?(track.id)

        @report.add_error(:track_album_reference_missing, 'Track does not belong to an exported album', track_id: track.id, jan_code: track.jan_code)
      end
    end

    def validate_relations
      @catalog.circle_albums.each do |relation|
        next if @circle_by_id.key?(relation.circle_id) && @album_by_id.key?(relation.album_id)

        @report.add_error(
          :circle_album_reference_missing,
          'Circle/album relation points to an unexported record',
          relation_id: relation.id,
          circle_id: relation.circle_id,
          album_id: relation.album_id
        )
      end

      @catalog.track_original_songs.each do |relation|
        next if @track_by_id.key?(relation.track_id) && @original_song_by_code.key?(relation.original_song_code)

        @report.add_error(
          :track_original_song_reference_missing,
          'Track/original song relation points to an unexported record',
          relation_id: relation.id,
          track_id: relation.track_id,
          original_song_code: relation.original_song_code
        )
      end

      @catalog.original_songs.each do |original_song|
        next if @original_by_code.key?(original_song.original_code)

        @report.add_error(
          :original_reference_missing,
          'Original song points to an unexported original',
          original_song_code: original_song.code,
          original_code: original_song.original_code
        )
      end
    end

    def validate_service_records
      SERVICE_DEFINITIONS.each do |service, definition|
        service_name = definition.fetch(:service)
        albums = @catalog.service_albums.fetch(service)
        tracks = @catalog.service_tracks.fetch(service)
        @service_album_by_id[service] = albums.index_by(&:id)

        validate_unique_service_values(
          albums,
          definition.fetch(:album_external_id),
          service_name,
          :duplicate_service_album_id,
          key: ->(record) { record.album_id }
        )
        validate_unique_service_values(
          tracks,
          definition.fetch(:track_external_id),
          service_name,
          :duplicate_service_track_id,
          key: ->(record) { record.public_send(definition.fetch(:provider_album_fk)) }
        )

        albums.each do |service_album|
          validate_service_album(service_album, service_name, definition)
        end
        tracks.each do |service_track|
          validate_service_track(service_track, service_name, definition)
        end
      end
    end

    def validate_service_album(service_album, service_name, definition)
      unless @album_by_id.key?(service_album.album_id)
        @report.add_error(
          :service_album_reference_missing,
          'Service album points to an unexported canonical album',
          service: service_name,
          service_album_record_id: service_album.id,
          album_id: service_album.album_id
        )
      end

      external_id = service_album.public_send(definition.fetch(:album_external_id))
      @report.add_error(:missing_service_album_id, 'Service album external ID is blank', service: service_name, service_album_record_id: service_album.id) if external_id.blank?
      @report.add_error(:missing_service_album_name, 'Service album name is blank', service: service_name, service_album_record_id: service_album.id) if service_album.name.blank?
      validate_url(service_album.url, :invalid_service_album_url, service_name, service_album.id) if service_album.url.present?
    end

    def validate_service_track(service_track, service_name, definition)
      provider_album_id = service_track.public_send(definition.fetch(:provider_album_fk))
      service_album = @service_album_by_id.fetch(service_name.to_sym, {})[provider_album_id]
      unless service_album
        @report.add_error(
          :service_track_album_reference_missing,
          'Service track points to an unexported service album',
          service: service_name,
          service_track_record_id: service_track.id,
          service_album_record_id: provider_album_id
        )
      end

      album = @album_by_id[service_track.album_id]
      track = @track_by_id[service_track.track_id]
      @report.add_error(:service_track_album_missing, 'Service track canonical album is missing', service: service_name, service_track_record_id: service_track.id, album_id: service_track.album_id) unless album
      @report.add_error(:service_track_track_missing, 'Service track canonical track is missing', service: service_name, service_track_record_id: service_track.id, track_id: service_track.track_id) unless track

      if service_album && service_track.album_id != service_album.album_id
        @report.add_error(
          :service_track_parent_mismatch,
          'Service track canonical album differs from its service album parent',
          service: service_name,
          service_track_record_id: service_track.id,
          service_album_record_id: service_album.id,
          service_album_album_id: service_album.album_id,
          service_track_album_id: service_track.album_id,
          track_id: service_track.track_id
        )
      end

      if album && track && album.jan_code != track.jan_code
        @report.add_error(
          :service_track_canonical_mismatch,
          'Service track canonical track belongs to another album',
          service: service_name,
          service_track_record_id: service_track.id,
          album_id: album.id,
          track_id: track.id,
          album_jan_code: album.jan_code,
          track_jan_code: track.jan_code
        )
      end

      external_id = service_track.public_send(definition.fetch(:track_external_id))
      @report.add_error(:missing_service_track_id, 'Service track external ID is blank', service: service_name, service_track_record_id: service_track.id) if external_id.blank?
      @report.add_error(:missing_service_track_name, 'Service track name is blank', service: service_name, service_track_record_id: service_track.id) if service_track.name.blank?
      validate_url(service_track.url, :invalid_service_track_url, service_name, service_track.id) if service_track.url.present?
    end

    def validate_unique_ids(records, attribute, code)
      duplicates = records.group_by { |record| record.public_send(attribute) }.select { |value, rows| value.present? && rows.length > 1 }
      duplicates.each do |value, rows|
        @report.add_error(code, "Duplicate #{attribute}", attribute => value, record_ids: rows.map(&:id))
      end
    end

    def validate_unique_values(records, attribute, code)
      validate_unique_ids(records, attribute, code)
    end

    def validate_unique_service_values(records, attribute, service, code, key:)
      duplicates = records.group_by { |record| [key.call(record), record.public_send(attribute)] }
                          .select { |(_parent_id, value), rows| value.present? && rows.length > 1 }
      duplicates.each do |(parent_id, _value), rows|
        @report.add_warning(code, 'Duplicate service external ID within the same service parent is retained as a separate provider relation', service:, parent_id:, record_ids: rows.map(&:id))
      end
    end

    def validate_url(url, code, service, record_id)
      uri = URI.parse(url.to_s)
      return if %w[http https].include?(uri.scheme) && uri.host.present?

      @report.add_error(code, 'URL must be an absolute HTTP(S) URL', service:, record_id:, url:)
    rescue URI::InvalidURIError
      @report.add_error(code, 'URL is invalid', service:, record_id:, url:)
    end

    def add_warnings
      add_non_touhou_track_warnings
      add_service_coverage_warnings
      add_release_date_warnings
      add_distribution_warnings
    end

    def add_non_touhou_track_warnings
      @catalog.tracks.reject(&:is_touhou).each do |track|
        @report.add_warning(:non_touhou_track_in_album, 'Non-Touhou track is retained in an exported Touhou album', track_id: track.id, jan_code: track.jan_code)
      end
    end

    def add_service_coverage_warnings
      SERVICE_DEFINITIONS.each_key do |service|
        albums = @catalog.service_albums.fetch(service)
        counts = albums.group_by(&:album_id)
        @catalog.albums.each do |album|
          record_count = counts.fetch(album.id, []).length
          next if record_count.positive?

          @report.add_warning(:service_album_unavailable, 'No service album is linked to the canonical album', service: SERVICE_DEFINITIONS.fetch(service).fetch(:service), album_id: album.id)
        end

        counts.each do |album_id, rows|
          next unless rows.length > 1

          @report.add_warning(:multiple_service_albums, 'Multiple service album records are retained for one canonical album', service: SERVICE_DEFINITIONS.fetch(service).fetch(:service), album_id:, record_ids: rows.map(&:id))
        end
      end

      @catalog.albums.each do |album|
        next if album.image_url.present?

        @report.add_warning(:missing_album_image, 'Canonical album has no image URL', album_id: album.id)
      end
    end

    def add_release_date_warnings
      @catalog.release_resolutions.each do |album_id, resolution|
        dates = resolution.candidates.map { |candidate| candidate.fetch(:date) }.uniq
        next unless dates.length > 1

        @report.add_warning(:release_date_conflict, 'Multiple source release dates exist; earliest date was selected', album_id:, dates: dates.map(&:iso8601), selected: resolution.release_date&.iso8601)
      end
    end

    def add_distribution_warnings
      @catalog.service_albums.fetch(:ytmusic).each do |ytmusic_album|
        next if ytmusic_album.distribution_source.blank? || %w[art_track_mode all_track_mode single_track].include?(ytmusic_album.distribution_source)

        @report.add_warning(
          :distribution_not_normal,
          'YouTube Music distribution date is not from a normal calculation',
          album_id: ytmusic_album.album_id,
          ytmusic_album_record_id: ytmusic_album.id,
          distribution_source: ytmusic_album.distribution_source
        )
      end
    end
  end
end
