# frozen_string_literal: true

module Admin
  class OriginalSongAssignmentsController < BaseController
    before_action :authenticate_admin_if_configured

    STATUS_OPTIONS = %w[missing present all].freeze
    PASTED_ORIGINAL_SONG_DELIMITER_PATTERN = %r{[,、，/／]+}

    def index
      @track_resource = Admin::Resource.find!('tracks')
      @query = params.fetch(:q, '').to_s.strip
      @status = normalized_status
      @show_identifiers = show_identifiers?
      @pagy, @tracks = pagy(:offset, assignment_scope, limit: Admin::Resource::DEFAULT_ITEMS)
    end

    def update
      errors = update_assignments

      if errors.empty?
        redirect_to admin_track_original_song_assignments_path(redirect_filter_params),
                    notice: t('admin.original_song_assignments.update_success')
      else
        redirect_to admin_track_original_song_assignments_path(redirect_filter_params),
                    alert: errors.join("\n")
      end
    end

    def options
      render json: { options: original_song_options }
    end

    def resolve
      render json: { resolutions: pasted_original_song_resolutions }
    end

    private

    def assignment_scope
      scope = @track_resource.apply_to(Track.all).reorder(nil)
      scope = @track_resource.search(scope, @query)
      scope = filter_by_status(scope)
      order_assignment_scope(scope)
    end

    def filter_by_status(scope)
      case @status
      when 'missing'
        scope.where(id: Track.missing_original_songs.select(:id))
      when 'present'
        scope.where(id: Track.where.associated(:original_songs).distinct.select(:id))
      else
        scope
      end
    end

    def order_assignment_scope(scope)
      scope.reorder(
        Arel.sql("#{Track.quoted_table_name}.#{Track.connection.quote_column_name(:jan_code)} DESC"),
        Arel.sql("#{assignment_disc_number_sql} ASC"),
        Arel.sql("#{assignment_track_number_sql} ASC"),
        Arel.sql("#{Track.quoted_table_name}.#{Track.connection.quote_column_name(:isrc)} ASC")
      )
    end

    def assignment_disc_number_sql
      <<~SQL.squish
        COALESCE(
          (#{active_spotify_track_position_sql(:disc_number)}),
          (#{streaming_track_position_sql(AppleMusicTrack, :disc_number)}),
          (#{streaming_track_position_sql(LineMusicTrack, :disc_number)}),
          (#{streaming_track_position_sql(SpotifyTrack, :disc_number)}),
          1
        )
      SQL
    end

    def assignment_track_number_sql
      <<~SQL.squish
        COALESCE(
          (#{active_spotify_track_position_sql(:track_number)}),
          (#{streaming_track_position_sql(AppleMusicTrack, :track_number)}),
          (#{streaming_track_position_sql(LineMusicTrack, :track_number)}),
          (#{streaming_track_position_sql(YtmusicTrack, :track_number)}),
          (#{streaming_track_position_sql(SpotifyTrack, :track_number)}),
          2147483647
        )
      SQL
    end

    def active_spotify_track_position_sql(column)
      spotify_tracks_table = SpotifyTrack.quoted_table_name
      spotify_albums_table = SpotifyAlbum.quoted_table_name
      <<~SQL.squish
        SELECT MIN(#{spotify_tracks_table}.#{SpotifyTrack.connection.quote_column_name(column)})
        FROM #{spotify_tracks_table}
        INNER JOIN #{spotify_albums_table}
          ON #{spotify_albums_table}.#{SpotifyAlbum.connection.quote_column_name(:id)}
           = #{spotify_tracks_table}.#{SpotifyTrack.connection.quote_column_name(:spotify_album_id)}
        WHERE #{spotify_tracks_table}.#{SpotifyTrack.connection.quote_column_name(:track_id)}
          = #{Track.quoted_table_name}.#{Track.connection.quote_column_name(:id)}
          AND #{spotify_albums_table}.#{SpotifyAlbum.connection.quote_column_name(:active)} = TRUE
      SQL
    end

    def streaming_track_position_sql(model_class, column)
      table = model_class.quoted_table_name
      <<~SQL.squish
        SELECT MIN(#{table}.#{model_class.connection.quote_column_name(column)})
        FROM #{table}
        WHERE #{table}.#{model_class.connection.quote_column_name(:track_id)}
          = #{Track.quoted_table_name}.#{Track.connection.quote_column_name(:id)}
      SQL
    end

    def normalized_status
      status = params.fetch(:status, 'missing').to_s
      STATUS_OPTIONS.include?(status) ? status : 'missing'
    end

    def show_identifiers?
      Array(params.fetch(:show_identifiers, '0')).map(&:to_s).include?('1')
    end

    def update_assignments
      errors = []
      assignments = assignment_params
      return [t('admin.original_song_assignments.no_assignments')] if assignments.empty?

      tracks = Track.where(id: assignments.keys).index_by { |track| track.id.to_s }

      Track.transaction do
        assignments.each do |track_id, assignment|
          track = tracks[track_id.to_s]
          if track.blank?
            errors << t('admin.original_song_assignments.track_not_found', id: track_id)
            next
          end

          codes = normalize_original_song_codes(assignment['original_song_codes'])
          original_songs = OriginalSong.non_duplicated.where(code: codes).index_by(&:code)
          missing_codes = codes - original_songs.keys
          if missing_codes.any?
            errors << t('admin.original_song_assignments.original_songs_not_found', isrc: track.isrc, codes: missing_codes.join(', '))
            next
          end

          track.original_songs = codes.map { |code| original_songs.fetch(code) }
        end

        raise ActiveRecord::Rollback if errors.any?
      end

      errors
    end

    def assignment_params
      assignments = params.fetch(:assignments, {})
      assignments.respond_to?(:to_unsafe_h) ? assignments.to_unsafe_h : assignments.to_h
    end

    def normalize_original_song_codes(value)
      value.to_s.split(%r{[\s,/]+}).map(&:strip).compact_blank.uniq
    end

    def original_song_options
      original_song_scope.limit(Admin::Resource::FORM_ASSOCIATION_AUTOCOMPLETE_LIMIT).map do |original_song|
        original_song_option(original_song)
      end
    end

    def pasted_original_song_resolutions
      pasted_original_song_queries.map do |query|
        {
          query:,
          options: candidate_original_songs(query).limit(10).map { |original_song| original_song_option(original_song) }
        }
      end
    end

    def pasted_original_song_queries
      params.fetch(:text, '').to_s.each_line.flat_map do |line|
        pasted_original_song_queries_from_line(line)
      end.compact_blank.uniq.first(30)
    end

    def pasted_original_song_queries_from_line(line)
      query = normalize_pasted_original_song_query(line)
      return [] if query.blank?

      split_pasted_original_song_query(query)
    end

    def split_pasted_original_song_query(query)
      return [query] if candidate_original_songs(query).exists?

      fragments = query.split(PASTED_ORIGINAL_SONG_DELIMITER_PATTERN)
      return [query] if fragments.map { |fragment| normalize_pasted_original_song_query(fragment) }.compact_blank.one?

      delimiters = query.scan(PASTED_ORIGINAL_SONG_DELIMITER_PATTERN)
      queries = []
      fragment_index = 0
      while fragment_index < fragments.length
        match = longest_pasted_original_song_query_match(fragments, delimiters, fragment_index)
        if match.present?
          queries << match.fetch(:query)
          fragment_index = match.fetch(:next_index)
        else
          queries << normalize_pasted_original_song_query(fragments.fetch(fragment_index))
          fragment_index += 1
        end
      end
      queries
    end

    def longest_pasted_original_song_query_match(fragments, delimiters, start_index)
      (fragments.length - 1).downto(start_index) do |end_index|
        query = joined_pasted_original_song_query(fragments, delimiters, start_index, end_index)
        return { query:, next_index: end_index + 1 } if candidate_original_songs(query).exists?
      end

      nil
    end

    def joined_pasted_original_song_query(fragments, delimiters, start_index, end_index)
      query = (start_index..end_index).each_with_object(+'') do |fragment_index, joined_query|
        joined_query << delimiters.fetch(fragment_index - 1, '') if fragment_index > start_index
        joined_query << fragments.fetch(fragment_index)
      end
      normalize_pasted_original_song_query(query)
    end

    def normalize_pasted_original_song_query(query)
      query.to_s
           .strip
           .then { |value| value.match?(/\A["'`]{3,}\z/) ? '' : value }
           .sub(/\A原曲\s*[:：]\s*/, '')
           .strip
    end

    def candidate_original_songs(query)
      exact_code_scope = original_song_base_scope.where(code: query)
      return exact_code_scope.order(:original_code, :track_number, :code) if exact_code_scope.exists?

      exact_title_scope = original_song_base_scope.where(title: query)
      return exact_title_scope.order(:original_code, :track_number, :code) if exact_title_scope.exists?

      search_original_songs(original_song_base_scope, query).order(:original_code, :track_number, :code)
    end

    def original_song_scope
      query = params.fetch(:q, '').to_s.strip
      scope = original_song_base_scope
      scope = search_original_songs(scope, query) if query.present?
      scope.order(:original_code, :track_number, :code)
    end

    def original_song_base_scope
      OriginalSong.non_duplicated.includes(:original)
    end

    def search_original_songs(scope, query)
      pattern = "%#{OriginalSong.sanitize_sql_like(query)}%"
      normalized_terms = normalized_original_song_query(query).split.flat_map do |term|
        normalized_original_song_search_terms(term)
      end
      conditions = {
        query: pattern
      }
      normalized_term_clause = normalized_terms.each_with_index.map do |term, index|
        conditions[:"normalized_term_#{index}"] = "%#{OriginalSong.sanitize_sql_like(term)}%"
        if term == '～'
          conditions[:"normalized_term_ascii_#{index}"] = '%~%'
          term_conditions = <<~SQL.squish
            (
              original_songs.title ILIKE :normalized_term_#{index} OR
              original_songs.title ILIKE :normalized_term_ascii_#{index} OR
              originals.title ILIKE :normalized_term_#{index} OR
              originals.title ILIKE :normalized_term_ascii_#{index} OR
              originals.short_title ILIKE :normalized_term_#{index} OR
              originals.short_title ILIKE :normalized_term_ascii_#{index}
            )
          SQL
          next term_conditions
        end

        <<~SQL.squish
          (
            original_songs.title ILIKE :normalized_term_#{index} OR
            originals.title ILIKE :normalized_term_#{index} OR
            originals.short_title ILIKE :normalized_term_#{index}
          )
        SQL
      end.join(' AND ')
      normalized_term_sql = normalized_term_clause.present? ? "OR (#{normalized_term_clause})" : nil

      scope.left_joins(:original).where(
        <<~SQL.squish,
          (
            original_songs.code ILIKE :query OR
            original_songs.title ILIKE :query OR
            original_songs.composer ILIKE :query OR
            originals.title ILIKE :query OR
            originals.short_title ILIKE :query
          )
          #{normalized_term_sql}
        SQL
        conditions
      )
    end

    def normalized_original_song_query(query)
      query.to_s
           .tr('　', ' ')
           .gsub(/[~〜～]/, ' ～ ')
           .squish
    end

    def normalized_original_song_search_terms(term)
      punctuation_normalized_term = term.delete('?!？！')
      return [punctuation_normalized_term] if punctuation_normalized_term.present?

      [term]
    end

    def original_song_label(original_song)
      [
        original_song.code,
        original_song.title,
        original_song.original_title,
        original_song.composer
      ].compact_blank.uniq.join(' / ')
    end

    def original_song_option(original_song)
      {
        value: original_song.code,
        label: original_song_label(original_song)
      }
    end

    def redirect_filter_params
      params.permit(:q, :status, :show_identifiers).to_h.compact_blank
    end
  end
end
