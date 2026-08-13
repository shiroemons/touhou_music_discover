# frozen_string_literal: true

module CatalogSnapshot
  class ReleaseDateResolver
    SERVICE_PRIORITY = %w[spotify apple_music line_music ytmusic].freeze

    Resolution = Struct.new(
      :release_date, :release_year, :source, :candidates,
      keyword_init: true
    )

    def initialize(service_albums)
      @service_albums = service_albums
    end

    def resolve
      exact_candidates = SERVICE_PRIORITY.first(3).flat_map do |service|
        Array(@service_albums.fetch(service.to_sym, [])).filter_map do |record|
          date = record.release_date
          next if date.blank?

          { service:, record_id: record.id.to_s, date: }
        end
      end

      ytmusic_candidates = Array(@service_albums.fetch(:ytmusic, [])).filter_map do |record|
        date = record.original_released_on
        next if date.blank?

        { service: 'ytmusic', record_id: record.id.to_s, date: }
      end

      candidates = exact_candidates.presence || ytmusic_candidates
      selected = candidates.min_by do |candidate|
        [candidate.fetch(:date), SERVICE_PRIORITY.index(candidate.fetch(:service)), candidate.fetch(:record_id)]
      end
      release_date = selected&.fetch(:date)

      release_year = if release_date
                       release_date.year
                     else
                       release_year_from_ytmusic
                     end

      Resolution.new(
        release_date:,
        release_year:,
        source: selected&.fetch(:service),
        candidates:
      )
    end

    private

    def release_year_from_ytmusic
      years = Array(@service_albums.fetch(:ytmusic, [])).filter_map do |record|
        year = record.release_year.to_s
        year if year.match?(/\A\d{4}\z/)
      end
      years.min
    end
  end
end
