# frozen_string_literal: true

module OriginalSongAssignments
  class Transfer
    SERVICE_PRIORITY = {
      spotify: 0,
      apple_music: 1,
      line_music: 2,
      ytmusic: 3
    }.freeze

    CatalogRow = Data.define(
      :service,
      :album_id,
      :platform_album_id,
      :album_name,
      :declared_total,
      :track_id,
      :track_name,
      :isrc,
      :disc_number,
      :track_number
    )
    TrackEntry = Data.define(:track_id, :track_name, :isrc, :disc_number, :track_number) do
      def position
        [disc_number, track_number]
      end
    end
    Snapshot = Data.define(:album_id, :jan_code, :album_name, :service, :circle_ids, :circle_names, :entries) do
      def track_signature
        entries.map { |entry| [entry.disc_number, entry.track_number, Transfer.normalize(entry.track_name)] }
      end

      def entry_at(position)
        entries.find { |entry| entry.position == position }
      end
    end
    CatalogPair = Data.define(:target, :source)
    AssignmentMetadata = Data.define(:track_metadata, :original_song_titles)
    OriginalSongLabel = Data.define(:code, :title)
    TrackComparison = Data.define(
      :disc_number,
      :track_number,
      :target_track_id,
      :target_isrc,
      :target_track_name,
      :source_track_id,
      :source_isrc,
      :source_track_name,
      :match_basis,
      :title_similarity_percent
    )
    CatalogMatch = Data.define(
      :target_jan_code,
      :source_jan_code,
      :album_name,
      :circle_names,
      :target_service,
      :source_service,
      :tracks
    )
    Assignment = Data.define(
      :target_track_id,
      :target_jan_code,
      :target_isrc,
      :source_track_ids,
      :source_jan_code,
      :source_isrc,
      :circle_names,
      :album_name,
      :target_service,
      :source_service,
      :disc_number,
      :track_number,
      :track_name,
      :original_song_codes,
      :original_song_labels
    )
    Conflict = Data.define(
      :target_track_id,
      :target_jan_code,
      :target_isrc,
      :album_name,
      :track_name,
      :assignment_sets
    )
    Rejection = Data.define(
      :target_jan_code,
      :source_jan_code,
      :album_name,
      :target_circle_names,
      :source_circle_names,
      :target_track_count,
      :source_track_count,
      :reasons
    )
    Plan = Data.define(:assignments, :matches, :conflicts, :rejections, :missing_track_count) do
      def links_to_add
        assignments.sum { |assignment| assignment.original_song_codes.size }
      end

      def unmatched_track_count
        missing_track_count - assignments.size - conflicts.size
      end
    end
    Result = Data.define(:assigned_tracks, :created_links, :skipped_tracks, :plan)

    class << self
      def normalize(value)
        value.to_s
             .unicode_normalize(:nfkc)
             .downcase
             .gsub(/[[:space:]]+/, ' ')
             .strip
      end

      def title_similarity_percent(first, second)
        first_chars = normalize(first).chars
        second_chars = normalize(second).chars
        return 100 if first_chars == second_chars
        return 0 if first_chars.empty? || second_chars.empty?

        distance = levenshtein_distance(first_chars, second_chars)
        ((1.0 - distance.fdiv([first_chars.size, second_chars.size].max)) * 100).round.clamp(0, 100)
      end

      private

      def levenshtein_distance(first_chars, second_chars)
        previous_row = (0..second_chars.size).to_a
        first_chars.each_with_index do |first_character, first_index|
          current_row = [first_index + 1]
          second_chars.each_with_index do |second_character, second_index|
            substitution_cost = first_character == second_character ? 0 : 1
            current_row << [
              current_row.fetch(second_index) + 1,
              previous_row.fetch(second_index + 1) + 1,
              previous_row.fetch(second_index) + substitution_cost
            ].min
          end
          previous_row = current_row
        end
        previous_row.last
      end
    end

    def plan(album_ids: nil)
      missing_scope = Track.unscoped.where.missing(:original_songs)
      missing_scope = missing_scope.where(jan_code: Album.unscoped.where(id: album_ids).select(:jan_code)) if album_ids.present?
      missing_track_ids = missing_scope.pluck(:id)
      return empty_plan if missing_track_ids.empty?

      target_album_ids = Album.unscoped.where(jan_code: missing_scope.select(:jan_code)).pluck(:id)
      target_snapshots = build_snapshots(target_album_ids)
      target_album_keys = target_snapshots.to_set { |snapshot| self.class.normalize(snapshot.album_name) }
      source_album_ids = catalog_album_headers.filter_map do |album_id, album_name|
        album_id if target_album_keys.include?(self.class.normalize(album_name))
      end
      snapshots = build_snapshots((target_album_ids + source_album_ids).uniq)
      snapshots_by_album = snapshots.group_by(&:album_id)
      links_by_track = original_song_codes_by_track
      track_metadata = track_metadata_for(snapshots)
      original_song_titles = OriginalSong.unscoped.pluck(:code, :title).to_h
      assignment_metadata = AssignmentMetadata.new(track_metadata:, original_song_titles:)
      missing_track_id_set = missing_track_ids.to_set
      source_album_id_set = snapshots_by_album.filter_map do |album_id, album_snapshots|
        album_id if album_snapshots.any? { |snapshot| snapshot.entries.any? { |entry| links_by_track.key?(entry.track_id) } }
      end.to_set

      assignments = []
      matches = []
      conflicts = []
      rejections = []

      target_album_ids.each do |target_album_id|
        target_album_snapshots = snapshots_by_album.fetch(target_album_id, [])
        next if target_album_snapshots.empty?

        target_album_names = target_album_snapshots.to_set { |snapshot| self.class.normalize(snapshot.album_name) }
        source_album_candidates = snapshots_by_album.filter_map do |source_album_id, source_album_snapshots|
          next if source_album_id == target_album_id || source_album_id_set.exclude?(source_album_id)

          source_album_names = source_album_snapshots.to_set { |snapshot| self.class.normalize(snapshot.album_name) }
          [source_album_id, source_album_snapshots] if target_album_names.intersect?(source_album_names)
        end
        compatible_pairs = source_album_candidates.filter_map do |_, source_album_snapshots|
          representative_target = preferred_snapshot(target_album_snapshots)
          representative_source = preferred_snapshot(source_album_snapshots)
          reasons = circle_rejection_reasons(representative_target, representative_source)
          pair = best_catalog_pair(target_album_snapshots, source_album_snapshots)
          reasons << :track_list_mismatch if pair.blank?

          if reasons.empty?
            pair
          else
            rejections << build_rejection(representative_target, representative_source, reasons)
            nil
          end
        end
        compatible_pairs.each { |pair| matches << build_catalog_match(pair, track_metadata) }

        missing_track_ids_for_album = target_album_snapshots
                                      .flat_map { |snapshot| snapshot.entries.map(&:track_id) }
                                      .select { |track_id| missing_track_id_set.include?(track_id) }
                                      .uniq
        missing_track_ids_for_album.each do |missing_track_id|
          source_entries = compatible_pairs.filter_map do |pair|
            target_entry = pair.target.entries.find { |entry| entry.track_id == missing_track_id }
            next if target_entry.blank?

            source_entry = pair.source.entry_at(target_entry.position)
            codes = links_by_track[source_entry&.track_id]
            [pair, target_entry, source_entry, codes] if source_entry.present? && codes.present?
          end
          next if source_entries.empty?

          assignment_sets = source_entries.map { |(_, _, _, codes)| codes }.uniq
          selected_pair, target_entry, = source_entries.min_by do |pair, _, source_entry, _|
            pair_sort_key(pair, source_entry)
          end
          if assignment_sets.one?
            assignments << build_assignment(
              selected_pair,
              target_entry,
              source_entries,
              assignment_sets.first,
              assignment_metadata
            )
          else
            conflicts << build_conflict(selected_pair.target, target_entry, assignment_sets, track_metadata)
          end
        end
      end

      assignment_album_pairs = assignments.to_set do |assignment|
        [assignment.target_jan_code, assignment.source_jan_code]
      end
      actionable_matches = matches.select do |match|
        assignment_album_pairs.include?([match.target_jan_code, match.source_jan_code])
      end
      Plan.new(
        assignments: assignments.sort_by { |assignment| assignment_sort_key(assignment) },
        matches: actionable_matches.uniq.sort_by { |match| [match.target_jan_code, match.source_jan_code] },
        conflicts: conflicts.sort_by { |conflict| [conflict.target_jan_code, conflict.target_isrc] },
        rejections: rejections.uniq.sort_by { |rejection| [rejection.target_jan_code, rejection.source_jan_code] },
        missing_track_count: missing_track_ids.size
      )
    end

    def apply!(album_ids: nil, progress_callback: nil)
      result = nil

      Track.transaction do
        current_plan = plan(album_ids:)
        validate_original_song_codes!(current_plan)
        progress_callback&.call(current: 0, total: current_plan.assignments.size, reset: true)

        assigned_tracks = 0
        created_links = 0
        skipped_tracks = 0

        current_plan.assignments.each.with_index(1) do |assignment, index|
          track = Track.unscoped.lock.find(assignment.target_track_id)
          if track.tracks_original_songs.exists?
            skipped_tracks += 1
          else
            assignment.original_song_codes.each do |original_song_code|
              TracksOriginalSong.create!(track:, original_song_code:)
              created_links += 1
            end
            assigned_tracks += 1
          end

          progress_callback&.call(
            current: index,
            total: current_plan.assignments.size,
            message: "原曲を紐づけています: #{assignment.album_name} / #{assignment.track_name}"
          )
        end

        result = Result.new(assigned_tracks:, created_links:, skipped_tracks:, plan: current_plan)
      end

      result
    end

    private

    def empty_plan
      Plan.new(assignments: [], matches: [], conflicts: [], rejections: [], missing_track_count: 0)
    end

    def catalog_album_headers
      [
        SpotifyAlbum.unscoped.where(active: true).pluck(:album_id, :name),
        AppleMusicAlbum.unscoped.where.not(album_id: nil).pluck(:album_id, :name),
        LineMusicAlbum.unscoped.pluck(:album_id, :name),
        YtmusicAlbum.unscoped.pluck(:album_id, :name)
      ].flatten(1).uniq
    end

    def build_snapshots(album_ids)
      return [] if album_ids.empty?

      album_metadata = Album.unscoped.where(id: album_ids).pluck(:id, :jan_code).to_h
      circle_data = circles_by_album(album_ids)
      grouped_rows = catalog_rows(album_ids).group_by do |row|
        [row.service, row.album_id, row.platform_album_id]
      end

      grouped_rows.filter_map do |(_, album_id, _), rows|
        snapshot_from_rows(rows, album_metadata, circle_data) if album_metadata.key?(album_id)
      end
    end

    def snapshot_from_rows(rows, album_metadata, circle_data)
      first = rows.first
      declared_total = first.declared_total.to_i
      entries = rows.map do |row|
        TrackEntry.new(
          track_id: row.track_id,
          track_name: row.track_name,
          isrc: row.isrc,
          disc_number: normalized_disc_number(row.disc_number),
          track_number: row.track_number.to_i
        )
      end
      return if declared_total <= 0 || entries.size != declared_total
      return if entries.any? { |entry| entry.track_name.blank? || entry.track_number <= 0 }
      return if entries.map(&:position).uniq.size != entries.size
      return unless contiguous_track_positions?(entries)

      circles = circle_data.fetch(first.album_id, { ids: [], names: [] })
      Snapshot.new(
        album_id: first.album_id,
        jan_code: album_metadata.fetch(first.album_id),
        album_name: first.album_name,
        service: first.service,
        circle_ids: circles.fetch(:ids),
        circle_names: circles.fetch(:names),
        entries: entries.sort_by(&:position)
      )
    end

    def normalized_disc_number(value)
      value.to_i.positive? ? value.to_i : 1
    end

    def contiguous_track_positions?(entries)
      entries.group_by(&:disc_number).all? do |_, disc_entries|
        disc_entries.map(&:track_number).sort == (1..disc_entries.size).to_a
      end
    end

    def circles_by_album(album_ids)
      result = Hash.new { |hash, key| hash[key] = { ids: [], names: [] } }
      CirclesAlbum.unscoped.joins(:circle).where(album_id: album_ids).pluck(:album_id, :circle_id, 'circles.name').each do |album_id, circle_id, circle_name|
        result[album_id][:ids] << circle_id
        result[album_id][:names] << circle_name
      end
      result.each_value do |circles|
        circles[:ids].uniq!
        circles[:names].uniq!
        circles[:names].sort!
      end
      result
    end

    def catalog_rows(album_ids)
      spotify_catalog_rows(album_ids) +
        apple_music_catalog_rows(album_ids) +
        line_music_catalog_rows(album_ids) +
        ytmusic_catalog_rows(album_ids)
    end

    def spotify_catalog_rows(album_ids)
      SpotifyTrack.unscoped
                  .joins(:spotify_album, :track)
                  .where(spotify_albums: { album_id: album_ids, active: true })
                  .pluck(
                    'spotify_albums.album_id',
                    'spotify_albums.id',
                    'spotify_albums.name',
                    'spotify_albums.total_tracks',
                    'spotify_tracks.track_id',
                    'spotify_tracks.name',
                    'tracks.isrc',
                    'spotify_tracks.disc_number',
                    'spotify_tracks.track_number'
                  ).map { |values| CatalogRow.new(service: :spotify, **catalog_row_attributes(values)) }
    end

    def apple_music_catalog_rows(album_ids)
      AppleMusicTrack.unscoped
                     .joins(:apple_music_album, :track)
                     .where(apple_music_albums: { album_id: album_ids })
                     .pluck(
                       'apple_music_albums.album_id',
                       'apple_music_albums.id',
                       'apple_music_albums.name',
                       'apple_music_albums.total_tracks',
                       'apple_music_tracks.track_id',
                       'apple_music_tracks.name',
                       'tracks.isrc',
                       'apple_music_tracks.disc_number',
                       'apple_music_tracks.track_number'
                     ).map { |values| CatalogRow.new(service: :apple_music, **catalog_row_attributes(values)) }
    end

    def line_music_catalog_rows(album_ids)
      LineMusicTrack.unscoped
                    .joins(:line_music_album, :track)
                    .where(line_music_albums: { album_id: album_ids })
                    .pluck(
                      'line_music_albums.album_id',
                      'line_music_albums.id',
                      'line_music_albums.name',
                      'line_music_albums.total_tracks',
                      'line_music_tracks.track_id',
                      'line_music_tracks.name',
                      'tracks.isrc',
                      'line_music_tracks.disc_number',
                      'line_music_tracks.track_number'
                    ).map { |values| CatalogRow.new(service: :line_music, **catalog_row_attributes(values)) }
    end

    def ytmusic_catalog_rows(album_ids)
      YtmusicTrack.unscoped
                  .joins(:ytmusic_album, :track)
                  .where(ytmusic_albums: { album_id: album_ids })
                  .pluck(
                    'ytmusic_albums.album_id',
                    'ytmusic_albums.id',
                    'ytmusic_albums.name',
                    'ytmusic_albums.total_tracks',
                    'ytmusic_tracks.track_id',
                    'ytmusic_tracks.name',
                    'tracks.isrc',
                    Arel.sql('1'),
                    'ytmusic_tracks.track_number'
                  ).map { |values| CatalogRow.new(service: :ytmusic, **catalog_row_attributes(values)) }
    end

    def catalog_row_attributes(values)
      keys = %i[album_id platform_album_id album_name declared_total track_id track_name isrc disc_number track_number]
      keys.zip(values).to_h
    end

    def original_song_codes_by_track
      result = TracksOriginalSong.unscoped
                                 .pluck(:track_id, :original_song_code)
                                 .each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(track_id, code), codes_by_track|
        codes_by_track[track_id] << code
      end
      result.each_value { |codes| codes.sort!.uniq! }
      result
    end

    def track_metadata_for(snapshots)
      track_ids = snapshots.flat_map { |snapshot| snapshot.entries.map(&:track_id) }.uniq
      Track.unscoped.where(id: track_ids).pluck(:id, :isrc).to_h
    end

    def circle_rejection_reasons(target, source)
      reasons = []
      if target.circle_ids.empty? || source.circle_ids.empty?
        reasons << :circle_missing
      elsif !target.circle_ids.intersect?(source.circle_ids)
        reasons << :circle_mismatch
      end
      reasons
    end

    def preferred_snapshot(snapshots)
      snapshots.min_by { |snapshot| SERVICE_PRIORITY.fetch(snapshot.service) }
    end

    def best_catalog_pair(target_snapshots, source_snapshots)
      pairs = target_snapshots.product(source_snapshots).filter_map do |target, source|
        next unless self.class.normalize(target.album_name) == self.class.normalize(source.album_name)
        next unless matching_track_catalogs?(target, source)

        CatalogPair.new(target:, source:)
      end
      pairs.min_by { |pair| catalog_pair_sort_key(pair) }
    end

    def matching_track_catalogs?(target, source)
      return false unless target.entries.map(&:position) == source.entries.map(&:position)

      target.entries.zip(source.entries).all? do |target_entry, source_entry|
        track_identity_basis(target_entry, source_entry).present?
      end
    end

    def track_identity_basis(target_entry, source_entry)
      exact_title_matches = target_entry.track_name.to_s == source_entry.track_name.to_s
      normalized_title_matches = self.class.normalize(target_entry.track_name) == self.class.normalize(source_entry.track_name)
      isrc_matches = target_entry.isrc.present? && target_entry.isrc == source_entry.isrc
      return :title_and_isrc if exact_title_matches && isrc_matches
      return :normalized_title_and_isrc if normalized_title_matches && isrc_matches
      return :title if exact_title_matches
      return :normalized_title if normalized_title_matches

      :isrc if isrc_matches
    end

    def catalog_pair_sort_key(pair)
      target_priority = SERVICE_PRIORITY.fetch(pair.target.service)
      source_priority = SERVICE_PRIORITY.fetch(pair.source.service)
      normalized_titles = pair.target.track_signature == pair.source.track_signature
      [normalized_titles ? 0 : 1, pair.target.service == pair.source.service ? 0 : 1,
       target_priority + source_priority, target_priority, source_priority]
    end

    def pair_sort_key(pair, source_entry)
      [*catalog_pair_sort_key(pair), pair.source.jan_code, source_entry.track_id]
    end

    def build_rejection(target, source, reasons)
      Rejection.new(
        target_jan_code: target.jan_code,
        source_jan_code: source.jan_code,
        album_name: target.album_name,
        target_circle_names: target.circle_names,
        source_circle_names: source.circle_names,
        target_track_count: target.entries.size,
        source_track_count: source.entries.size,
        reasons:
      )
    end

    def build_assignment(pair, target_entry, source_entries, original_song_codes, metadata)
      selected_pair, _, selected_entry, = source_entries.min_by do |candidate_pair, _, entry, _|
        pair_sort_key(candidate_pair, entry)
      end
      target = pair.target
      source = selected_pair.source
      Assignment.new(
        target_track_id: target_entry.track_id,
        target_jan_code: target.jan_code,
        target_isrc: metadata.track_metadata.fetch(target_entry.track_id),
        source_track_ids: source_entries.map { |(_, _, entry, _)| entry.track_id }.uniq,
        source_jan_code: source.jan_code,
        source_isrc: metadata.track_metadata.fetch(selected_entry.track_id),
        circle_names: target.circle_names,
        album_name: target.album_name,
        target_service: target.service,
        source_service: source.service,
        disc_number: target_entry.disc_number,
        track_number: target_entry.track_number,
        track_name: target_entry.track_name,
        original_song_codes:,
        original_song_labels: original_song_codes.map do |code|
          OriginalSongLabel.new(code:, title: metadata.original_song_titles.fetch(code, nil))
        end
      )
    end

    def build_catalog_match(pair, track_metadata)
      comparisons = pair.target.entries.map do |target_entry|
        source_entry = pair.source.entry_at(target_entry.position)
        TrackComparison.new(
          disc_number: target_entry.disc_number,
          track_number: target_entry.track_number,
          target_track_id: target_entry.track_id,
          target_isrc: track_metadata.fetch(target_entry.track_id),
          target_track_name: target_entry.track_name,
          source_track_id: source_entry.track_id,
          source_isrc: track_metadata.fetch(source_entry.track_id),
          source_track_name: source_entry.track_name,
          match_basis: track_identity_basis(target_entry, source_entry),
          title_similarity_percent: self.class.title_similarity_percent(target_entry.track_name, source_entry.track_name)
        )
      end

      CatalogMatch.new(
        target_jan_code: pair.target.jan_code,
        source_jan_code: pair.source.jan_code,
        album_name: pair.target.album_name,
        circle_names: pair.target.circle_names,
        target_service: pair.target.service,
        source_service: pair.source.service,
        tracks: comparisons
      )
    end

    def build_conflict(target, target_entry, assignment_sets, track_metadata)
      Conflict.new(
        target_track_id: target_entry.track_id,
        target_jan_code: target.jan_code,
        target_isrc: track_metadata.fetch(target_entry.track_id),
        album_name: target.album_name,
        track_name: target_entry.track_name,
        assignment_sets:
      )
    end

    def assignment_sort_key(assignment)
      [assignment.target_jan_code, assignment.disc_number, assignment.track_number, assignment.target_isrc]
    end

    def validate_original_song_codes!(current_plan)
      expected_codes = current_plan.assignments.flat_map(&:original_song_codes).uniq
      existing_codes = OriginalSong.unscoped.where(code: expected_codes).pluck(:code)
      missing_codes = expected_codes - existing_codes
      return if missing_codes.empty?

      raise ActiveRecord::RecordNotFound, "移行元の原曲が見つかりません: #{missing_codes.join(', ')}"
    end
  end
end
