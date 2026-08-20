# frozen_string_literal: true

class LineMusicAlbumReplacementDetector
  Plan = Data.define(:line_music_album, :candidates, :queries, :errors) do
    def ready?
      errors.empty? && candidates.any?
    end

    def candidate_count
      candidates.size
    end
  end

  Result = Data.define(:candidate_count, :candidate_ids)

  def initialize(line_music_album:)
    @line_music_album = line_music_album
  end

  def prepare
    queries = search_queries
    candidates = queries.flat_map do |query|
      Array(LineMusicAlbum.with_retry(max_attempts: 3) { LineMusic::Album.search(query) })
    end

    candidates = candidates
                 .select { |line_album| replacement_candidate?(line_album) }
                 .uniq(&:album_id)
                 .sort_by { |line_album| [line_album.release_date || Date.new(1900, 1, 1), line_album.album_id] }

    Plan.new(@line_music_album, candidates, queries, [])
  rescue StandardError => e
    Rails.logger.error("LINE MUSIC置換候補の検出に失敗しました: #{e.class} - #{e.message}")
    Plan.new(@line_music_album, [], queries || [], [user_facing_error(e)])
  end

  def detect!
    plan = prepare
    raise Error, plan.errors.join(' / ') unless plan.errors.empty?

    candidates = plan.candidates.filter_map do |line_album|
      LineMusicAlbumReplacementCandidate.record_from_api!(
        line_music_album: @line_music_album,
        line_album:
      )
    end

    Result.new(candidates.size, candidates.map(&:line_music_id))
  end

  class Error < StandardError; end

  private

  def search_queries
    source_albums = [@line_music_album.album&.spotify_album, @line_music_album.album&.apple_music_album].compact
    names = [@line_music_album.name, *source_albums.map(&:name)].compact_blank
    artist_names = source_albums.filter_map { |source| source.artist_name.presence }

    [*names, *names.product(artist_names).map { |name, artist| [name, artist].join(' ') }]
      .map { |query| query.to_s.strip }
      .compact_blank
      .uniq
  end

  def replacement_candidate?(line_album)
    return false if line_album.blank? || line_album.album_id.blank?
    return false if line_album.album_id == @line_music_album.line_music_id

    source_albums = [@line_music_album.album&.spotify_album, @line_music_album.album&.apple_music_album].compact
    source_albums = [@line_music_album] if source_albums.empty?
    source_albums.any? { |source_album| LineMusicAlbum.matches_album?(line_album, source_album) }
  end

  def user_facing_error(error)
    return 'LINE MUSIC APIへの接続に失敗しました。時間をおいて再試行してください。' if error.is_a?(Faraday::Error)

    "候補検出に失敗しました: #{error.message}"
  end
end
