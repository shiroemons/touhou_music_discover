# frozen_string_literal: true

class AlbumTitleResolver
  SERVICE_DEFINITIONS = {
    spotify: { album_class_name: 'SpotifyAlbum', track_association: :spotify_tracks, active: true },
    apple_music: { album_class_name: 'AppleMusicAlbum', track_association: :apple_music_tracks },
    ytmusic: { album_class_name: 'YtmusicAlbum', track_association: :ytmusic_tracks },
    line_music: { album_class_name: 'LineMusicAlbum', track_association: :line_music_tracks }
  }.freeze
  SERVICE_PRIORITY = SERVICE_DEFINITIONS.keys.each_with_index.to_h.freeze

  Candidate = Struct.new(
    :service,
    :album_record,
    :tracks,
    :tracks_by_track_id,
    :usable,
    :reasons,
    :japanese_count,
    :name_count,
    :album_japanese,
    keyword_init: true
  ) do
    def album_name
      AlbumTitleNormalizer.normalize(album_record&.name)
    end

    def track_name_count
      tracks.count { |track| AlbumTitleNormalizer.normalize(track.name).present? }
    end

    def japanese_ratio
      return 0.0 if name_count.zero?

      japanese_count.to_f / name_count
    end

    def japanese_preferred?
      album_japanese || japanese_ratio >= 0.5
    end

    def fallback_available?
      album_name.present? && (tracks.any? || total_tracks_zero?)
    end

    def total_tracks_zero?
      album_record.respond_to?(:total_tracks) && album_record.total_tracks.to_i.zero?
    end

    def updated_at_score
      album_record.updated_at ? album_record.updated_at.to_i : 0
    end
  end

  Resolution = Struct.new(
    :album,
    :source,
    :mode,
    :status,
    :candidate,
    :candidates,
    :manual_override,
    keyword_init: true
  ) do
    def display_album_name
      candidate&.album_name.presence || album.jan_code
    end

    alias_method :display_name, :display_album_name

    def display_track_name(track)
      track_catalog = candidate&.tracks_by_track_id
      track_record = track_catalog&.fetch(track.id, nil)
      raw_name = track_record&.name
      AlbumTitleNormalizer.normalize(raw_name).presence || track.isrc
    end

    def japanese_count
      candidate&.japanese_count.to_i
    end

    def name_count
      candidate&.name_count.to_i
    end

    def coverage
      [japanese_count, name_count]
    end

    def fallback?
      status != :ok
    end

    def override?
      mode == :override
    end

    def invalid_override?
      status == :invalid_override
    end
  end

  class << self
    def for(album)
      return unless album

      new(album).resolve
    end

    def for_many(albums)
      albums = Array(albums).compact
      return {} if albums.empty?

      album_ids = albums.map(&:id).uniq
      expected_track_ids_by_jan = Track.unscoped
                                       .where(jan_code: albums.map(&:jan_code).uniq)
                                       .pluck(:jan_code, :id)
                                       .group_by(&:first)
                                       .transform_values { |rows| rows.to_set(&:last) }
      records_by_service = SERVICE_DEFINITIONS.to_h do |service, definition|
        model = definition.fetch(:album_class_name).constantize
        relation = model.unscoped.where(album_id: album_ids)
        relation = relation.where(active: true) if definition[:active]
        records = relation.includes(definition.fetch(:track_association) => :track).to_a
        [service, records.group_by(&:album_id)]
      end

      albums.to_h do |album|
        platform_albums = SERVICE_DEFINITIONS.keys.index_with do |service|
          records_by_service.fetch(service).fetch(album.id, [])
        end
        [album.id, new(album, platform_albums:, expected_track_ids: expected_track_ids_by_jan.fetch(album.jan_code, Set.new)).resolve]
      end
    end
  end

  def initialize(album, platform_albums: nil, expected_track_ids: nil)
    @album = album
    @platform_albums = platform_albums || load_platform_albums
    @expected_track_ids = expected_track_ids || Track.unscoped.where(jan_code: album.jan_code).pluck(:id).to_set
  end

  def resolve
    candidates = SERVICE_DEFINITIONS.keys.flat_map do |service|
      @platform_albums.fetch(service, []).map { |platform_album| assess(service, platform_album) }
    end

    manual_override = @album.title_source_override.presence
    override_candidate = candidate_for_override(candidates, manual_override)
    if manual_override.present? && override_candidate&.usable
      return Resolution.new(
        album: @album,
        source: override_candidate.service,
        mode: :override,
        status: :ok,
        candidate: override_candidate,
        candidates:,
        manual_override:
      )
    end

    selected = select_candidate(candidates.select(&:usable))
    status = if manual_override.present?
               :invalid_override
             elsif selected
               :ok
             else
               :unavailable
             end

    selected ||= select_candidate(candidates.select(&:fallback_available?))
    status = :invalid_override if manual_override.present?

    Resolution.new(
      album: @album,
      source: selected&.service,
      mode: :auto,
      status:,
      candidate: selected,
      candidates:,
      manual_override:
    )
  end

  private

  def load_platform_albums
    SERVICE_DEFINITIONS.to_h do |service, definition|
      model = definition.fetch(:album_class_name).constantize
      relation = model.unscoped.where(album_id: @album.id)
      relation = relation.where(active: true) if definition[:active]
      [service, relation.includes(definition.fetch(:track_association) => :track).to_a]
    end
  end

  def candidate_for_override(candidates, override)
    return if override.blank?

    service = override.to_sym
    return unless SERVICE_DEFINITIONS.key?(service)

    candidates
      .select { |candidate| candidate.service == service }
      .max_by { |candidate| [candidate.usable ? 1 : 0, *candidate_selection_score(candidate, prefer_service: true)] }
  end

  def select_candidate(candidates)
    return if candidates.empty?

    japanese_candidates = candidates.select(&:japanese_preferred?)
    if japanese_candidates.any?
      japanese_candidates.max_by { |candidate| candidate_selection_score(candidate) }
    else
      candidates.max_by { |candidate| candidate_fallback_score(candidate) }
    end
  end

  def candidate_selection_score(candidate, prefer_service: false)
    [
      candidate.japanese_ratio,
      candidate.japanese_count,
      candidate.album_japanese ? 1 : 0,
      candidate.track_name_count,
      prefer_service ? 1 : -SERVICE_PRIORITY.fetch(candidate.service),
      candidate.updated_at_score,
      candidate.album_record.id.to_s
    ]
  end

  def candidate_fallback_score(candidate)
    [
      -SERVICE_PRIORITY.fetch(candidate.service),
      candidate.track_name_count,
      candidate.updated_at_score,
      candidate.album_record.id.to_s
    ]
  end

  def assess(service, platform_album)
    definition = SERVICE_DEFINITIONS.fetch(service)
    tracks = platform_album.public_send(definition.fetch(:track_association)).to_a
    track_ids = tracks.map(&:track_id)
    reasons = []

    reasons << :missing_album_name if AlbumTitleNormalizer.normalize(platform_album.name).blank?
    reasons << :duplicate_track_ids if track_ids.compact.uniq.length != track_ids.compact.length
    reasons << :missing_track_ids if track_ids.any?(&:blank?)
    reasons << :missing_tracks if (@expected_track_ids - track_ids.to_set).any?
    reasons << :unrelated_tracks if (track_ids.to_set - @expected_track_ids).any?
    reasons << :missing_track_names if tracks.any? { |track| AlbumTitleNormalizer.normalize(track.name).blank? }

    reasons << :track_count_mismatch if platform_album.respond_to?(:total_tracks) && platform_album.total_tracks.present? && platform_album.total_tracks.to_i != tracks.length

    unless service == :ytmusic
      positions = tracks.map { |track| [track.disc_number, track.track_number] }
      reasons << :missing_track_positions if positions.any? { |disc, number| disc.blank? || number.blank? }
      reasons << :duplicate_track_positions if positions.uniq.length != positions.length
    end

    name_tracks = tracks.select { |track| @expected_track_ids.include?(track.track_id) }
    japanese_count = name_tracks.count { |track| AlbumTitleNormalizer.japanese?(track.name) }
    name_count = name_tracks.count { |track| AlbumTitleNormalizer.normalize(track.name).present? }

    Candidate.new(
      service:,
      album_record: platform_album,
      tracks:,
      tracks_by_track_id: tracks.index_by(&:track_id),
      usable: reasons.empty?,
      reasons: reasons.freeze,
      japanese_count:,
      name_count:,
      album_japanese: AlbumTitleNormalizer.japanese?(platform_album.name)
    )
  end
end
