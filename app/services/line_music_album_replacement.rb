# frozen_string_literal: true

require 'uri'

class LineMusicAlbumReplacement
  Plan = Data.define(
    :line_music_album,
    :new_album,
    :new_tracks,
    :mappings,
    :new_url,
    :expected_old_line_music_id,
    :before_snapshot,
    :preview_after_snapshot,
    :diff,
    :errors
  ) do
    def ready?
      errors.empty?
    end

    def old_line_music_id
      line_music_album.line_music_id
    end

    def new_line_music_id
      new_album&.album_id
    end
  end

  Result = Data.define(:old_line_music_id, :new_line_music_id, :created_count, :updated_count, :removed_count)

  class Error < StandardError; end

  class << self
    def default_url(line_music_id)
      "https://music.line.me/webapp/album/#{line_music_id}"
    end
  end

  def initialize(line_music_album:, new_line_music_id:, new_url: nil, expected_old_line_music_id: nil)
    @line_music_album = line_music_album
    @new_line_music_id = new_line_music_id.to_s.strip
    @new_url = new_url.to_s.strip.presence
    @expected_old_line_music_id = expected_old_line_music_id.to_s.strip.presence
  end

  def prepare
    target = LineMusicAlbum.unscoped.includes(:album).find(@line_music_album.id)
    errors = validate_input(target)
    return invalid_plan(target, errors) if errors.any?

    new_album = LineMusicAlbum.with_retry(max_attempts: 3) { LineMusic::Album.find(@new_line_music_id) }
    errors.concat(validate_album(target, new_album))
    return invalid_plan(target, errors, new_album:) if errors.any?

    new_tracks = LineMusicAlbum.with_retry(max_attempts: 3) { LineMusic::Album.tracks(@new_line_music_id) }
    errors.concat(validate_track_catalog(target, new_album, new_tracks))
    source_track_sets = LineMusicTrack.source_track_sets_for(target.album)
    mappings = LineMusicTrack.build_track_mappings(source_track_sets, new_tracks)
    errors.concat(validate_mappings(target, new_tracks, mappings))

    new_url = normalized_url(@new_url || self.class.default_url(@new_line_music_id), @new_line_music_id)
    errors << new_url if new_url.is_a?(String) && new_url.start_with?('URL_INVALID:')
    new_url = nil if new_url.is_a?(String) && new_url.start_with?('URL_INVALID:')

    before_snapshot = snapshot(target, LineMusicTrack.unscoped.where(line_music_album_id: target.id))
    preview_after_snapshot = snapshot_for_plan(target, new_album, mappings, new_url)
    diff = build_diff(target, mappings)

    Plan.new(
      target,
      new_album,
      new_tracks,
      mappings,
      new_url,
      @expected_old_line_music_id || target.line_music_id,
      before_snapshot,
      preview_after_snapshot,
      diff,
      errors
    )
  rescue ActiveRecord::RecordNotFound
    Plan.new(@line_music_album, nil, [], [], nil, @expected_old_line_music_id, {}, {}, {}, ['対象のLINE MUSICアルバムが見つかりません。'])
  rescue StandardError => e
    Rails.logger.error("LINE MUSICアルバム置換のプレビューに失敗しました: #{e.class} - #{e.message}")
    Plan.new(@line_music_album, nil, [], [], nil, @expected_old_line_music_id, {}, {}, {}, [user_facing_error(e)])
  end

  def apply!(action_run_id: nil)
    plan = prepare
    raise Error, plan.errors.join(' / ') unless plan.ready?

    result = nil
    LineMusicAlbum.transaction do
      target = LineMusicAlbum.unscoped.lock.find(@line_music_album.id)
      ensure_current_target!(target, plan)
      current_tracks = LineMusicTrack.unscoped.where(line_music_album_id: target.id).lock.to_a
      ensure_current_tracks!(current_tracks, plan.before_snapshot.fetch('tracks', []))

      rows_by_track_id = current_tracks.index_by { |line_track| line_track.track_id.to_s }
      rows_by_line_music_id = current_tracks.index_by(&:line_music_id)
      ensure_external_id_collisions!(rows_by_line_music_id, plan.mappings)

      target.update!(
        line_music_id: plan.new_line_music_id,
        name: plan.new_album.album_title,
        url: plan.new_url,
        release_date: plan.new_album.release_date,
        total_tracks: plan.new_album.track_total_count,
        payload: plan.new_album.as_json
      )

      created_count = 0
      updated_count = 0
      plan.mappings.each do |mapping|
        source_track = mapping.fetch(:source)
        line_track = mapping.fetch(:line)
        existing = rows_by_track_id.delete(source_track.track_id.to_s)
        attributes = track_attributes(target, source_track, line_track)

        if existing
          existing.update!(attributes)
          updated_count += 1
        else
          LineMusicTrack.create!(attributes.merge(line_music_album_id: target.id))
          created_count += 1
        end
      end

      removed_count = rows_by_track_id.size
      LineMusicTrack.unscoped.where(id: rows_by_track_id.values.map(&:id)).delete_all if rows_by_track_id.any?

      after_snapshot = snapshot(target.reload, LineMusicTrack.unscoped.where(line_music_album_id: target.id))
      LineMusicAlbumReplacementHistory.create!(
        line_music_album: target,
        old_line_music_id: plan.old_line_music_id,
        new_line_music_id: plan.new_line_music_id,
        old_url: plan.before_snapshot.dig('album', 'url'),
        new_url: plan.new_url,
        old_total_tracks: plan.before_snapshot.dig('album', 'total_tracks'),
        new_total_tracks: plan.new_album.track_total_count,
        before_snapshot: plan.before_snapshot,
        after_snapshot:,
        action_run_id:
      )
      LineMusicAlbumReplacementCandidate.where(
        line_music_album_id: target.id,
        line_music_id: plan.new_line_music_id
      ).find_each { |candidate| candidate.update!(status: 'applied') }

      result = Result.new(plan.old_line_music_id, plan.new_line_music_id, created_count, updated_count, removed_count)
    end
    result
  end

  private

  def validate_input(target)
    errors = []
    errors << '新しいLINE MUSICアルバムIDを入力してください。' if @new_line_music_id.blank?
    errors << 'LINE MUSICアルバムIDに空白は使えません。' if @new_line_music_id.match?(/\s/)
    errors << 'LINE MUSICアルバムIDは英数字・ハイフン・アンダースコアで入力してください。' if @new_line_music_id.present? && !@new_line_music_id.match?(/\A[[:alnum:]_-]+\z/)
    errors << '新しいLINE MUSICアルバムIDは現在のIDと異なる値を入力してください。' if target.line_music_id == @new_line_music_id
    errors << '対象アルバムの現在IDが変更されています。画面を開き直して再試行してください。' if @expected_old_line_music_id.present? && target.line_music_id != @expected_old_line_music_id
    errors << '入力した新しいIDは別のLINE MUSICアルバムで使用されています。先に重複を解消してください。' if LineMusicAlbum.unscoped.where(line_music_id: @new_line_music_id).where.not(id: target.id).exists?
    errors
  end

  def validate_album(target, new_album)
    return ['新しいLINE MUSICアルバムが見つかりません。'] if new_album.blank?
    return ['LINE MUSICアルバム名が取得できません。'] if new_album.album_title.blank?

    source_albums = [target.album&.spotify_album, target.album&.apple_music_album].compact
    source_albums = [target] if source_albums.empty?
    return [] if source_albums.any? { |source| LineMusicAlbum.matches_album?(new_album, source) }

    ['新しいIDはタイトル・発売日・アーティスト・曲数の照合条件を満たしません。']
  end

  def validate_track_catalog(_target, new_album, new_tracks)
    errors = []
    errors << "LINE MUSICアルバムの曲数が一致しません（アルバム情報: #{new_album.track_total_count}, API: #{new_tracks.size}）。" if new_album.track_total_count.to_i != new_tracks.size
    errors
  end

  def validate_mappings(target, new_tracks, mappings)
    errors = []
    errors << "全曲を一意に照合できません（照合済み: #{mappings.size}/#{new_tracks.size}）。更新は中止されます。" if mappings.size != new_tracks.size

    line_ids = mappings.map { |mapping| mapping.fetch(:line).track_id }
    source_ids = mappings.map { |mapping| mapping.fetch(:source).track_id }
    errors << 'LINE MUSICトラックIDに重複があります。' if line_ids.uniq.size != line_ids.size
    errors << '照合元トラックに重複があります。' if source_ids.uniq.size != source_ids.size
    invalid_source = source_ids.any? { |track_id| !Track.unscoped.exists?(id: track_id, jan_code: target.album.jan_code) }
    errors << '照合元トラックが対象アルバムに属していません。' if invalid_source
    errors
  end

  def normalized_url(value, line_music_id)
    uri = URI.parse(value)
    valid_host = uri.is_a?(URI::HTTPS) && uri.host == 'music.line.me' && uri.userinfo.blank?
    path_has_id = uri.path.to_s.split('/').include?(line_music_id)
    query_has_id = URI.decode_www_form(uri.query.to_s).any? do |key, query_value|
      key == 'item' && query_value == line_music_id
    end
    return value if valid_host && (path_has_id || query_has_id)

    "URL_INVALID: LINE MUSICのURLには新しいアルバムID #{line_music_id} を含めてください。"
  rescue URI::InvalidURIError
    'URL_INVALID: URLの形式が正しくありません。'
  end

  def invalid_plan(target, errors, new_album: nil)
    Plan.new(target, new_album, [], [], nil, @expected_old_line_music_id || target.line_music_id, {}, {}, {}, errors)
  end

  def snapshot(target, tracks)
    {
      'album' => target.attributes.slice('id', 'album_id', 'line_music_id', 'name', 'url', 'release_date', 'total_tracks', 'payload'),
      'tracks' => tracks.sort_by { |track| [track.disc_number.to_i, track.track_number.to_i, track.id.to_s] }.map do |track|
        track.attributes.slice('id', 'album_id', 'track_id', 'line_music_id', 'name', 'url', 'disc_number', 'track_number', 'payload')
      end
    }
  end

  def snapshot_for_plan(target, new_album, mappings, new_url)
    {
      'album' => {
        'id' => target.id,
        'album_id' => target.album_id,
        'line_music_id' => new_album&.album_id,
        'name' => new_album&.album_title,
        'url' => new_url,
        'release_date' => new_album&.release_date&.iso8601,
        'total_tracks' => new_album&.track_total_count,
        'payload' => new_album&.as_json
      },
      'tracks' => mappings.map do |mapping|
        source_track = mapping.fetch(:source)
        line_track = mapping.fetch(:line)
        {
          'track_id' => source_track.track_id,
          'line_music_id' => line_track.track_id,
          'name' => line_track.track_title,
          'url' => "https://music.line.me/webapp/track/#{line_track.track_id}",
          'disc_number' => line_track.disc_number,
          'track_number' => line_track.track_number,
          'payload' => line_track.as_json
        }
      end
    }
  end

  def build_diff(target, mappings)
    current_tracks = LineMusicTrack.unscoped.where(line_music_album_id: target.id).to_a
    current_by_track_id = current_tracks.index_by { |track| track.track_id.to_s }
    mapping_track_ids = mappings.map { |mapping| mapping.fetch(:source).track_id.to_s }
    {
      'created' => mapping_track_ids.count { |track_id| !current_by_track_id.key?(track_id) },
      'updated' => mapping_track_ids.count { |track_id| current_by_track_id.key?(track_id) },
      'removed' => current_tracks.count { |track| mapping_track_ids.exclude?(track.track_id.to_s) },
      'unchanged' => 0
    }
  end

  def ensure_current_target!(target, plan)
    return if target.line_music_id == plan.old_line_music_id

    raise Error, '対象アルバムの現在IDが変更されています。プレビューをやり直してください。'
  end

  def ensure_current_tracks!(current_tracks, planned_tracks)
    current_ids = current_tracks.map { |track| track.id.to_s }.sort
    planned_ids = planned_tracks.map { |track| track.fetch('id').to_s }.sort
    return if current_ids == planned_ids

    raise Error, '対象アルバムの楽曲データが変更されています。プレビューをやり直してください。'
  end

  def ensure_external_id_collisions!(rows_by_line_music_id, mappings)
    mappings.each do |mapping|
      line_id = mapping.fetch(:line).track_id
      existing = rows_by_line_music_id[line_id]
      next if existing.blank? || existing.track_id.to_s == mapping.fetch(:source).track_id.to_s

      raise Error, "新しいLINE MUSICトラックID #{line_id} が既存の別楽曲と衝突しています。"
    end
  end

  def track_attributes(target, source_track, line_track)
    {
      album_id: target.album_id,
      track_id: source_track.track_id,
      line_music_id: line_track.track_id,
      name: line_track.track_title,
      url: "https://music.line.me/webapp/track/#{line_track.track_id}",
      disc_number: line_track.disc_number,
      track_number: line_track.track_number,
      payload: line_track.as_json
    }
  end

  def user_facing_error(error)
    return 'LINE MUSIC APIへの接続に失敗しました。時間をおいて再試行してください。' if error.is_a?(Faraday::Error)

    "照合に失敗しました: #{error.message}"
  end
end
