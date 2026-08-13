# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'securerandom'
require 'uri'

module CatalogSnapshot
  SCHEMA_VERSION = 1
  DEFAULT_OUTPUT_DIR = Rails.root.join('tmp/catalog_snapshots')
  DISTRIBUTION_SOURCES = %w[art_track_mode all_track_mode single_track degraded failed corrected].freeze
  FORBIDDEN_EXPORT_KEYS = %w[
    payload cookie api_key oauth_token access_token video_id user_id email
  ].freeze

  SERVICE_DEFINITIONS = {
    spotify: {
      service: 'spotify',
      album_class_name: 'SpotifyAlbum',
      track_class_name: 'SpotifyTrack',
      album_external_id: :spotify_id,
      track_external_id: :spotify_id,
      provider_album_fk: :spotify_album_id,
      active: true
    },
    apple_music: {
      service: 'apple_music',
      album_class_name: 'AppleMusicAlbum',
      track_class_name: 'AppleMusicTrack',
      album_external_id: :apple_music_id,
      track_external_id: :apple_music_id,
      provider_album_fk: :apple_music_album_id,
      active: false
    },
    ytmusic: {
      service: 'ytmusic',
      album_class_name: 'YtmusicAlbum',
      track_class_name: 'YtmusicTrack',
      album_external_id: :browse_id,
      track_external_id: :video_id,
      provider_album_fk: :ytmusic_album_id,
      active: false
    },
    line_music: {
      service: 'line_music',
      album_class_name: 'LineMusicAlbum',
      track_class_name: 'LineMusicTrack',
      album_external_id: :line_music_id,
      track_external_id: :line_music_id,
      provider_album_fk: :line_music_album_id,
      active: false
    }
  }.freeze

  FILES = %w[
    albums.jsonl
    tracks.jsonl
    circles.jsonl
    originals.jsonl
    original_songs.jsonl
    circle_albums.jsonl
    track_original_songs.jsonl
    service_albums.jsonl
    service_tracks.jsonl
    aliases.jsonl
    quality_report.json
  ].freeze

  class Error < StandardError
    attr_reader :report

    def initialize(message, report: nil)
      @report = report
      super(message)
    end
  end

  class QualityReport
    MAX_WARNING_SAMPLES = 100

    attr_reader :errors, :warnings, :warning_count

    def initialize
      @errors = []
      @warnings = []
      @warning_count = 0
    end

    def add_error(code, message, context = {})
      @errors << issue(code, message, context)
    end

    def add_warning(code, message, context = {})
      @warning_count += 1
      @warnings << issue(code, message, context) if @warnings.length < MAX_WARNING_SAMPLES
    end

    def valid?
      errors.empty?
    end

    def to_h
      {
        schema_version: SCHEMA_VERSION,
        valid: valid?,
        error_count: errors.length,
        warning_count:,
        errors:,
        warnings:
      }
    end

    private

    def issue(code, message, context)
      {
        code: code.to_s,
        message:,
        context: normalize_context(context)
      }
    end

    def normalize_context(value)
      case value
      when Hash
        value.to_h { |key, item| [key.to_s, normalize_context(item)] }
      when Array
        value.map { |item| normalize_context(item) }
      when Date, Time, DateTime
        value.iso8601
      else
        value
      end
    end
  end

  Catalog = Struct.new(
    :albums, :tracks, :circles, :originals, :original_songs,
    :circle_albums, :track_original_songs,
    :service_albums, :service_tracks,
    :title_resolutions, :release_resolutions,
    :expected_track_ids_by_jan,
    keyword_init: true
  )
end
