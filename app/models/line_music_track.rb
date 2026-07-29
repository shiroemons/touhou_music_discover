# frozen_string_literal: true

class LineMusicTrack < ApplicationRecord
  default_scope { includes(:album).order('albums.jan_code desc').order(disc_number: :asc).order(track_number: :asc) }

  belongs_to :album
  belongs_to :line_music_album
  belongs_to :track

  delegate :jan_code, :is_touhou, :circle_name, to: :album, allow_nil: true
  delegate :isrc, to: :track, allow_nil: true
  delegate :image_url, to: :line_music_album, allow_nil: true

  scope :line_music_id, ->(line_music_id) { find_by(line_music_id:) }
  scope :album_line_music_id, ->(line_music_id) { eager_load(:line_music_album).where(line_music_album: { line_music_id: }) }
  scope :is_touhou, -> { eager_load(:track).where(tracks: { is_touhou: true }) }
  scope :non_touhou, -> { eager_load(:track).where(tracks: { is_touhou: false }) }

  def self.fetch_tracks(progress_callback: nil)
    Rails.logger.info 'LINE MUSIC トラック取得処理を開始します'
    album_ids = Album.pluck(:id)
    total_count = album_ids.size
    Rails.logger.info "処理対象アルバム数: #{total_count}件"
    progress_callback&.call(
      current: 0,
      total: total_count,
      message: 'LINE MUSICトラックを取得しています',
      reset: true
    )

    processed_count = 0
    batch_size = 1000
    album_ids.each_slice(batch_size) do |ids|
      batch_count = ids.size
      Rails.logger.info "バッチ処理開始: #{batch_count}件"
      finish_callback = lambda do |album, _index, _result|
        processed_count += 1
        progress_callback&.call(
          current: processed_count,
          total: total_count,
          message: "LINE MUSICトラックを処理しています: #{album.jan_code}"
        )
      end

      Album.includes(
        { spotify_album: :spotify_tracks },
        { apple_music_album: :apple_music_tracks },
        { line_music_album: :line_music_tracks }
      ).where(id: ids).then do |records|
        ParallelRunner.each(records, workers: :line_music, finish: finish_callback) do |r|
          process_album(r)
        end
      end

      Rails.logger.info "バッチ処理完了: 合計 #{processed_count}/#{total_count}件処理済み"
    end
    Rails.logger.info 'LINE MUSIC トラック取得処理が完了しました'
  end

  def self.process_album(album)
    Rails.logger.info "アルバム処理: (ID: #{album.id})"

    if album.line_music_album.blank?
      Rails.logger.info 'LINE MUSIC アルバムが存在しないためスキップします'
      return
    end

    lm_album = album.line_music_album

    if lm_album.total_tracks == lm_album.line_music_tracks.size
      Rails.logger.info "すべてのトラックが既に登録済みのためスキップします: #{lm_album.name} (#{lm_album.line_music_tracks.size}/#{lm_album.total_tracks})"
      return
    end

    Rails.logger.info "トラック処理開始: #{lm_album.name} (現在: #{lm_album.line_music_tracks.size}/#{lm_album.total_tracks})"

    source_track_sets = source_track_sets_for(album)
    if source_track_sets.empty?
      Rails.logger.warn "照合元のSpotify / Apple Musicトラックが存在しないためスキップします: #{lm_album.name}"
      return
    end

    fetch_match_and_save_tracks(source_track_sets, lm_album)
    Rails.logger.info "トラック処理完了: #{lm_album.name} (現在: #{lm_album.line_music_tracks.reload.size}/#{lm_album.total_tracks})"
  end

  def self.match_and_save_tracks_for_spotify(spotify_album, line_music_album)
    source_track_set = build_source_track_set(:spotify, spotify_album, spotify_album.spotify_tracks)
    fetch_match_and_save_tracks([source_track_set], line_music_album)
  end

  def self.match_and_save_tracks_for_apple_music(apple_music_album, line_music_album)
    source_track_set = build_source_track_set(:apple_music, apple_music_album, apple_music_album.apple_music_tracks)
    fetch_match_and_save_tracks([source_track_set], line_music_album)
  end

  def self.source_track_sets_for(album)
    [
      build_source_track_set(:spotify, album.spotify_album, album.spotify_album&.spotify_tracks),
      build_source_track_set(:apple_music, album.apple_music_album, album.apple_music_album&.apple_music_tracks)
    ].compact
  end

  def self.build_source_track_set(service, streaming_album, tracks)
    return if streaming_album.blank?

    {
      service:,
      tracks: tracks.to_a,
      declared_total: streaming_album.total_tracks.to_i,
      fallback_priority: service == :spotify ? 1 : 0
    }
  end

  def self.fetch_match_and_save_tracks(source_track_sets, line_music_album)
    Rails.logger.info "LINE MUSIC トラック取得: アルバムID #{line_music_album.line_music_id}"

    with_retry(max_attempts: 3) do
      lm_tracks = LineMusic::Album.tracks(line_music_album.line_music_id)
      Rails.logger.info "LINE MUSIC トラック取得成功: #{lm_tracks.size}件"

      unless lm_tracks.size == line_music_album.total_tracks.to_i
        Rails.logger.warn(
          'LINE MUSIC APIのトラック件数がアルバム情報と一致しないため保存を中止します: ' \
          "#{lm_tracks.size} vs #{line_music_album.total_tracks}"
        )
        return
      end

      mappings = build_track_mappings(source_track_sets, lm_tracks)
      LineMusicTrack.transaction do
        mappings.each do |mapping|
          source_track = mapping.fetch(:source)
          line_track = mapping.fetch(:line)
          Rails.logger.info(
            "LINE MUSICトラック一致 (#{mapping.fetch(:strategy)}): " \
            "#{source_track.name} → #{line_track.track_title}"
          )
          save_track(source_track.album_id, source_track.track_id, line_music_album, line_track)
        end
      end

      mapped_line_ids = mappings.to_h { |mapping| [mapping.fetch(:line).track_id, true] }
      unmatched_line_tracks = lm_tracks.reject { |line_track| mapped_line_ids[line_track.track_id] }
      if unmatched_line_tracks.any?
        Rails.logger.warn(
          '誤紐付け防止のため保存しなかったLINE MUSICトラック: ' \
          "#{unmatched_line_tracks.map(&:track_title).join(' / ')}"
        )
      end

      Rails.logger.info "安全なマッチング完了: #{mappings.size}/#{lm_tracks.size}件"
    end
  end

  def self.build_track_mappings(source_track_sets, line_tracks)
    mappings = unique_title_mappings(source_track_sets, line_tracks)
    fallback_source = positional_fallback_source(source_track_sets, line_tracks)
    return mappings.sort_by { |mapping| track_position(mapping.fetch(:line)) } if fallback_source.blank?

    mapped_line_ids = mappings.to_h { |mapping| [mapping.fetch(:line).track_id, true] }
    mapped_source_ids = mappings.to_h { |mapping| [mapping.fetch(:source).track_id, true] }
    sources_by_position = unique_tracks_by_position(fallback_source.fetch(:tracks))

    line_tracks.each do |line_track|
      next if mapped_line_ids[line_track.track_id]

      source_track = sources_by_position[track_position(line_track)]
      next if source_track.blank? || mapped_source_ids[source_track.track_id]

      mappings << { source: source_track, line: line_track, strategy: :position }
      mapped_line_ids[line_track.track_id] = true
      mapped_source_ids[source_track.track_id] = true
    end

    mappings.sort_by { |mapping| track_position(mapping.fetch(:line)) }
  end

  def self.unique_title_mappings(source_track_sets, line_tracks)
    sources_by_title = source_track_sets
                       .flat_map { it.fetch(:tracks) }
                       .group_by { |track| normalized_track_title(track.name) }
    lines_by_title = line_tracks.group_by { |track| normalized_track_title(track.track_title) }

    (sources_by_title.keys & lines_by_title.keys).filter_map do |title|
      next if title.blank? || lines_by_title.fetch(title).size != 1

      source_tracks = sources_by_title.fetch(title).uniq(&:track_id)
      next if source_tracks.size != 1

      {
        source: source_tracks.first,
        line: lines_by_title.fetch(title).first,
        strategy: :title
      }
    end
  end

  def self.positional_fallback_source(source_track_sets, line_tracks)
    eligible_sources = source_track_sets.select do |source|
      tracks = source.fetch(:tracks)
      tracks.size == line_tracks.size &&
        source.fetch(:declared_total) == tracks.size &&
        positional_catalog_consistent?(tracks, line_tracks)
    end

    eligible_sources.max_by do |source|
      [
        positional_title_match_count(source.fetch(:tracks), line_tracks),
        source.fetch(:fallback_priority)
      ]
    end
  end

  def self.positional_catalog_consistent?(source_tracks, line_tracks)
    source_positions = source_tracks
                       .group_by { |track| normalized_track_title(track.name) }
                       .filter_map do |title, tracks|
                         [title, track_position(tracks.first)] if title.present? && tracks.one?
                       end
                       .to_h
    line_positions = line_tracks
                     .group_by { |track| normalized_track_title(track.track_title) }
                     .filter_map do |title, tracks|
                       [title, track_position(tracks.first)] if title.present? && tracks.one?
                     end
                     .to_h

    (source_positions.keys & line_positions.keys).all? do |title|
      source_positions.fetch(title) == line_positions.fetch(title)
    end
  end

  def self.positional_title_match_count(source_tracks, line_tracks)
    lines_by_position = unique_tracks_by_position(line_tracks)

    source_tracks.count do |source_track|
      line_track = lines_by_position[track_position(source_track)]
      line_track.present? && normalized_track_title(source_track.name) == normalized_track_title(line_track.track_title)
    end
  end

  def self.unique_tracks_by_position(tracks)
    tracks
      .group_by { |track| track_position(track) }
      .filter_map { |position, grouped_tracks| [position, grouped_tracks.first] if grouped_tracks.one? }
      .to_h
  end

  def self.track_position(track)
    [track.disc_number.to_i, track.track_number.to_i]
  end

  def self.normalized_track_title(title)
    LineMusicAlbum.normalize_text(title)
  end

  def self.save_track(album_id, track_id, lm_album, lm_track)
    url = "https://music.line.me/webapp/track/#{lm_track.track_id}"
    Rails.logger.info "LINE MUSIC トラック情報保存: #{lm_track.track_title} (ID: #{lm_track.track_id})"

    line_music_track = ::LineMusicTrack.find_or_create_by!(
      line_music_album_id: lm_album.id,
      line_music_id: lm_track.track_id
    ) do |record|
      record.album_id = album_id
      record.track_id = track_id
      record.name = lm_track.track_title
    end

    line_music_track.update!(
      album_id:,
      track_id:,
      name: lm_track.track_title,
      url:,
      disc_number: lm_track.disc_number,
      track_number: lm_track.track_number,
      payload: lm_track.as_json
    )
    Rails.logger.info "LINE MUSIC トラック情報を保存しました: #{lm_track.track_title}"
  end

  # リトライ機能を提供するヘルパーメソッド
  def self.with_retry(max_attempts: 3, retry_delay: 2)
    attempts = 0
    begin
      attempts += 1
      yield
    rescue Faraday::ConnectionFailed, Net::OpenTimeout => e
      if attempts < max_attempts
        Rails.logger.warn "接続エラーが発生しました。#{attempts}回目のリトライを実行します: #{e.message}"
        sleep retry_delay * attempts # 指数バックオフ
        retry
      else
        Rails.logger.error "最大リトライ回数(#{max_attempts}回)に達しました: #{e.message}"
        raise
      end
    end
  end

  def artist_name
    payload['artists']&.map { it['artist_name'] }&.join(' / ')
  end
end
