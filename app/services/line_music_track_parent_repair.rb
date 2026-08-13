# frozen_string_literal: true

class LineMusicTrackParentRepair
  LineTrack = Data.define(:track_id, :track_title, :disc_number, :track_number)
  Issue = Data.define(:line_music_track_id, :line_music_id, :reason)
  Repair = Data.define(
    :line_music_track,
    :source_track,
    :old_album_id,
    :old_track_id,
    :new_album_id,
    :new_track_id
  )
  Plan = Data.define(:line_music_album, :repairs, :issues) do
    def ready?
      issues.empty?
    end
  end
  Result = Data.define(:plans, :updated_count)

  class Error < StandardError; end

  def initialize(apply: false, line_music_album_ids: nil)
    @apply = apply
    @line_music_album_ids = line_music_album_ids&.compact_blank
  end

  def call
    plans = target_albums.map { |line_music_album| build_plan(line_music_album) }
    invalid_plans = plans.reject(&:ready?)
    raise Error, unresolved_message(invalid_plans) if @apply && invalid_plans.any?

    updated_count = @apply ? apply_plans!(plans) : 0
    Result.new(plans:, updated_count:)
  end

  private

  def target_albums
    scope = LineMusicAlbum.unscoped.where.not(album_id: nil)
    scope = scope.includes(:album, :line_music_tracks).order(:id)
    scope = scope.where(id: @line_music_album_ids) if @line_music_album_ids.present?

    scope.select do |line_music_album|
      line_music_album.line_music_tracks.any? do |line_music_track|
        invalid_track?(line_music_track, line_music_album.album)
      end
    end
  end

  def build_plan(line_music_album)
    target_album = line_music_album.album
    line_music_tracks = line_music_album.line_music_tracks.to_a
    invalid_tracks = line_music_tracks.select { |track| invalid_track?(track, target_album) }
    track_views = line_music_tracks.map do |line_music_track|
      LineTrack.new(
        track_id: line_music_track.line_music_id,
        track_title: line_music_track.name,
        disc_number: line_music_track.disc_number,
        track_number: line_music_track.track_number
      )
    end
    mappings_by_line_music_id = build_mappings(target_album, track_views).index_by { |mapping| mapping.fetch(:line).track_id }

    repairs = []
    issues = []
    invalid_tracks.each do |line_music_track|
      mapping = mappings_by_line_music_id[line_music_track.line_music_id]
      source_track = mapping&.fetch(:source)

      if source_track.blank?
        issues << Issue.new(line_music_track.id, line_music_track.line_music_id, 'canonical source track could not be matched')
        next
      end

      unless source_track.album_id == target_album.id && track_belongs_to_album?(source_track.track_id, target_album)
        issues << Issue.new(line_music_track.id, line_music_track.line_music_id, 'matched source track belongs to another canonical album')
        next
      end

      repairs << Repair.new(
        line_music_track,
        source_track,
        line_music_track.album_id,
        line_music_track.track_id,
        target_album.id,
        source_track.track_id
      )
    end

    Plan.new(line_music_album, repairs, issues)
  end

  def build_mappings(album, line_tracks)
    source_track_sets(album).then do |source_sets|
      return [] if source_sets.empty?

      LineMusicTrack.build_track_mappings(source_sets, line_tracks)
    end
  end

  def source_track_sets(album)
    [
      source_track_set(
        album,
        SpotifyAlbum.unscoped.find_by(album_id: album.id, active: true),
        SpotifyTrack,
        :spotify_album_id,
        fallback_priority: 1
      ),
      source_track_set(
        album,
        AppleMusicAlbum.unscoped.find_by(album_id: album.id),
        AppleMusicTrack,
        :apple_music_album_id,
        fallback_priority: 0
      )
    ].compact
  end

  def source_track_set(album, service_album, track_model, foreign_key, fallback_priority:)
    return if service_album.blank?

    {
      service: track_model.name,
      tracks: track_model.unscoped.where(foreign_key => service_album.id).order(:disc_number, :track_number, :id).to_a,
      declared_total: service_album.total_tracks.to_i,
      fallback_priority:
    }.tap do |source_set|
      source_set[:tracks] = source_set.fetch(:tracks).select { |track| track.album_id == album.id }
    end
  end

  def invalid_track?(line_music_track, target_album)
    line_music_track.album_id != target_album.id || !track_belongs_to_album?(line_music_track.track_id, target_album)
  end

  def track_belongs_to_album?(track_id, album)
    Track.unscoped.exists?(id: track_id, jan_code: album.jan_code)
  end

  def apply_plans!(plans)
    repairs = plans.flat_map(&:repairs)
    LineMusicTrack.transaction do
      repairs.each do |repair|
        repair.line_music_track.update!(
          album_id: repair.new_album_id,
          track_id: repair.new_track_id
        )
      end
    end
    repairs.size
  end

  def unresolved_message(plans)
    details = plans.flat_map do |plan|
      plan.issues.map do |issue|
        [
          issue.line_music_track_id,
          issue.line_music_id,
          issue.reason
        ].join(':')
      end
    end
    "LINE MUSICトラックのcanonical修復に失敗しました: #{details.join(', ')}"
  end
end
