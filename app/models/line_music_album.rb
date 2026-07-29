# frozen_string_literal: true

class LineMusicAlbum < ApplicationRecord
  MAX_STRICT_TRACK_COUNT_DIFFERENCE = 1

  default_scope { includes(:album).order('albums.jan_code desc') }

  has_many :line_music_tracks,
           -> { order(Arel.sql('line_music_tracks.disc_number ASC, line_music_tracks.track_number ASC')) },
           inverse_of: :line_music_album,
           dependent: :destroy

  belongs_to :album

  delegate :jan_code, :is_touhou, :circle_name, to: :album, allow_nil: true

  scope :line_music_id, ->(line_music_id) { find_by(line_music_id:) }
  scope :is_touhou, -> { eager_load(:album).where(albums: { is_touhou: true }) }
  scope :non_touhou, -> { eager_load(:album).where(albums: { is_touhou: false }) }
  scope :missing_album, -> { where.missing(:album) }

  JAN_TO_ALBUM_IDS = {
    '4580547318838' => 'mb000000000229658f', # 幽閉サテライト - 感情ケミストリー(Drum 'n' Bass Remix short ver.)
    '4580547319644' => 'mb00000000022bd013', # Various Artists - Edge
    '4580547320350' => 'mb00000000022967d4', # Crest - Dual Circulation Ⅱ
    '4580547320374' => 'mb0000000002296790', # Crest - Crest
    '4580547320381' => 'mb000000000229678f', # Crest - Dual CirculationⅢ
    '4580547320404' => 'mb00000000022967d9', # Crest - CrestⅡ
    '4580547320817' => 'mb0000000002296798', # Lunatico_fEs(ヤヤネヒロコ) - The mormental E.P - 少女洋琴倶楽部III-
    '4580547326758' => 'mb000000000229afcc', # 幽閉サテライト - 雅-MIYABI-SinglesBestvol.7～明鏡止水～
    '4580547336740' => 'mb000000000299dbcb', # 彩音 ～xi-on～ - BEST selection III -彩音 ～xi-on～ ベスト-
    '4580547337273' => 'mb0000000002afa6a9', # 凋叶棕 - 𠷡
    '4580547337495' => 'mb0000000002c776eb', # StarlessTrilogy - StarlessTrilogyII
    '4580547338485' => 'mb0000000002e9d62c', # 幽閉サテライト - 彩-IRODORI-Singles Best vol.8～穢れなきユーフォリア～
    '4580547338959' => 'mb00000000031ee6e5', # StarlessTrilogy - Ode to a VladⅢ
    '4580547339802' => 'mb00000000036874f9', # イノライ - ずんだもんが東方にやってきたのだ！
    '4582736131150' => 'mb0000000003ba6b5b', # 少女理論観測所 - showcase ⅳ
    '4582736133420' => 'mb00000000040ff58d', # TAMUSIC - 東方バイオリンロック X-XFD-(TOUHOU VIOLIN ROCK)
    '4582736134533' => 'mb00000000047a98ec', # fractrick - And what's gone？
    '4582736134762' => 'mb00000000047a98ee', # askey - 🤞
    '4582736137985' => 'mb000000000527116a', # 机上の空想理論 - ちぇあ’s 東方アレンジ せれくしょん。
    '4582736137800' => 'mb000000000526fa39', # イノライ - Valentine Mode♡ (feat. 小春六花 & 夢ノ結唱 POPY(SynthesizerV))
    '4582736137787' => 'mb000000000526fa77', # イノライ - 綺麗事だけの歌が嫌いだった
    '4582736137688' => 'mb000000000526fa66'  # POLTANEST - リジッドパラダイス ~ Reanimate
  }.freeze

  def self.fetch_albums(progress_callback: nil)
    Rails.logger.info 'LINE MUSIC アルバム取得処理を開始します'
    album_count = Album.includes(:spotify_album, :apple_music_album).missing_line_music_album.count
    Rails.logger.info "処理対象アルバム数: #{album_count}件"
    progress_callback&.call(
      current: 0,
      total: album_count,
      message: 'LINE MUSICアルバム候補を処理しています',
      reset: true
    )

    processed_count = 0
    Album.includes(:spotify_album, :apple_music_album).missing_line_music_album.find_each do |album|
      processed_count += 1
      Rails.logger.info "アルバム処理中 (#{processed_count}/#{album_count})"

      process_spotify_albums(album.spotify_album) if album.spotify_album.present?
      process_apple_music_albums(album.apple_music_album) if album.apple_music_album.present?

      Rails.logger.info "#{processed_count}件のアルバムを処理しました" if (processed_count % 10).zero?
      progress_callback&.call(
        current: processed_count,
        total: album_count,
        message: "LINE MUSICアルバム候補を処理しています: #{album.jan_code}"
      )
    end

    Rails.logger.info 'LINE MUSIC アルバム情報更新処理を開始します'
    update_line_music_album_info(progress_callback:)
    Rails.logger.info 'LINE MUSIC アルバム取得処理が完了しました'
  end

  def self.process_spotify_albums(s_album)
    Rails.logger.info "Spotifyアルバム処理: #{s_album.name} (JAN: #{s_album.album.jan_code})"

    line_album_id = JAN_TO_ALBUM_IDS[s_album.album.jan_code]
    if line_album_id.present?
      Rails.logger.info "JAN_TO_ALBUM_IDSに一致するLINE MUSIC IDが見つかりました: #{line_album_id}"
      return if find_and_save(line_album_id, s_album)

      Rails.logger.warn "JAN_TO_ALBUM_IDSの候補が一致条件を満たさないため、通常検索を続行します: #{line_album_id}"
    end

    # 最も正確な検索クエリから順番に試す
    artist_names = Array(s_album.payload&.fetch('artists', nil)).filter_map { it['name'].presence }.sort
    search_queries = [
      [s_album.name, artist_names.join(' ')].compact_blank.join(' '), # アーティスト名を空白区切りで結合
      [s_album.name, artist_names.first].compact_blank.join(' '), # 最初のアーティスト名のみ使用
      s_album.name # アルバム名のみ
    ]

    # 特殊文字の置換や正規化が必要な場合のみ追加のクエリを生成
    search_queries << s_album.name.tr('〜~', '～') if /[〜~～]/.match?(s_album.name)

    search_queries << s_album.name.unicode_normalize if s_album.name != s_album.name.unicode_normalize

    # かっこや括弧付きの追加情報を削除
    base_name = s_album.name.sub(/ [(|\[].*[)|\]]\z/, '')
    search_queries << base_name if base_name != s_album.name

    search_and_save_with_queries(search_queries.uniq, s_album)
  end

  def self.process_apple_music_albums(am_album)
    Rails.logger.info "Apple Musicアルバム処理: #{am_album.name}"

    # 最も正確な検索クエリから順番に試す
    artist_name = am_album.artist_name
    album_name = am_album.name.sub(' - EP', '') # EPの表記を削除

    search_queries = [
      [album_name, artist_name].compact_blank.join(' '), # アルバム名とアーティスト名
      am_album.name # 元のアルバム名
    ]

    # かっこや括弧付きの追加情報を削除
    base_name = am_album.name.sub(/ [(|\[].*[)|\]]\z/, '')
    search_queries << base_name if base_name != am_album.name

    search_and_save_with_queries(search_queries.uniq, am_album)
  end

  def self.update_line_music_album_info(progress_callback: nil)
    lm_album_ids = where(url: nil).pluck(:id)
    batch_size = 1000
    total_count = lm_album_ids.size
    Rails.logger.info "LINE MUSIC アルバム情報更新対象: #{total_count}件"
    return if total_count.zero?

    progress_callback&.call(
      current: 0,
      total: total_count,
      message: 'LINE MUSICアルバム情報を更新しています',
      reset: true
    )

    processed_count = 0
    lm_album_ids.each_slice(batch_size) do |ids|
      batch_count = ids.size
      Rails.logger.info "バッチ処理開始: #{batch_count}件"
      finish_callback = lambda do |_line_music_album, _index, _result|
        processed_count += 1
        progress_callback&.call(
          current: processed_count,
          total: total_count,
          message: "LINE MUSICアルバム情報を更新しています: #{processed_count}/#{total_count}"
        )
      end

      where(id: ids).then do |records|
        ParallelRunner.each(records, workers: :line_music, finish: finish_callback) do |line_music_album|
          with_retry(max_attempts: 3) do
            Rails.logger.info "LINE MUSIC アルバム情報取得: #{line_music_album.line_music_id}"
            lm_album = LineMusic::Album.find(line_music_album.line_music_id)

            if lm_album.blank?
              Rails.logger.warn "LINE MUSIC アルバムが見つかりませんでした: #{line_music_album.line_music_id}"
              next
            end

            line_music_album.update(
              name: lm_album.album_title,
              url: "https://music.line.me/webapp/album/#{line_music_album.line_music_id}",
              total_tracks: lm_album.track_total_count,
              release_date: lm_album.release_date,
              payload: lm_album.as_json
            )
            Rails.logger.info "LINE MUSIC アルバム情報を更新しました: #{lm_album.album_title}"
          end
        end
      end

      Rails.logger.info "バッチ処理完了: 合計 #{processed_count}/#{total_count}件処理済み"
    end
    Rails.logger.info "LINE MUSIC アルバム情報更新処理が完了しました: 合計 #{processed_count}件"
  end

  # LineMusicのアルバム情報を保存する
  def self.save_album(album_id, lm_album)
    return nil if lm_album.blank?

    album_title = lm_album.album_title.presence
    if album_title.blank?
      Rails.logger.warn "LINE MUSIC アルバム名が空のため保存をスキップしました: #{lm_album.album_id}"
      return nil
    end

    url = "https://music.line.me/webapp/album/#{lm_album.album_id}"
    Rails.logger.info "LINE MUSIC アルバム情報保存: #{album_title} (ID: #{lm_album.album_id})"

    line_music_album = ::LineMusicAlbum.find_or_initialize_by(line_music_id: lm_album.album_id)
    line_music_album.assign_attributes(
      album_id:,
      name: album_title,
      url:,
      release_date: lm_album.release_date,
      total_tracks: lm_album.track_total_count,
      payload: lm_album.as_json
    )
    line_music_album.save!
    Rails.logger.info "LINE MUSIC アルバム情報を保存しました: #{album_title}"
    line_music_album
  end

  # rubocop:disable Naming/PredicateMethod
  def self.search_and_save(query, album)
    Rails.logger.info "LINE MUSIC アルバム検索: #{query}"
    line_albums = LineMusic::Album.search(query)
    Rails.logger.info "検索結果: #{line_albums.total}件"

    case line_albums.total
    when 0
      Rails.logger.info "検索結果なし: #{query}"
      return false
    when 1
      line_album = line_albums.first
      if matches_album?(line_album, album)
        Rails.logger.info "一致するアルバムが見つかりました: #{line_album.album_title}"
        LineMusicAlbum.save_album(album.album_id, line_album)
        return true
      else
        Rails.logger.info "アルバムが条件に一致しませんでした: リリース日=#{line_album.release_date}, トラック数=#{line_album.track_total_count} vs #{album.total_tracks}"
        return false
      end
    else
      Rails.logger.info '複数の検索結果から条件に一致するアルバムを探しています'

      # トラック数が一致するアルバムを優先してフィルタリング
      matching_by_tracks = line_albums.select { |la| la.track_total_count == album.total_tracks }
      Rails.logger.info "トラック数が一致するアルバム: #{matching_by_tracks.size}件"

      if matching_by_tracks.any?
        # トラック数が一致する中から、タイトルと配信日またはアーティストが一致するものを優先して選択
        exact_title_match = matching_by_tracks.find do |la|
          title_matches?(la.album_title, album.name) && album_identity_matches?(la, album)
        end

        if exact_title_match
          Rails.logger.info "タイトルが完全一致するアルバムを選択: #{exact_title_match.album_title}"
          LineMusicAlbum.save_album(album.album_id, exact_title_match)
          return true
        end

        # リリース日が最も近いアルバムを選択
        closest_date_match = matching_by_tracks
                             .select { |la| title_matches?(la.album_title, album.name) }
                             .min_by { |la| (la.release_date - album.release_date).abs }
        if closest_date_match && release_date_matches?(closest_date_match, album)
          Rails.logger.info "リリース日が近いアルバムを選択: #{closest_date_match.album_title}, 日付差: #{release_date_difference(closest_date_match, album)}日"
          LineMusicAlbum.save_album(album.album_id, closest_date_match)
          return true
        end
      end

      # 条件に一致するアルバムをフィルタリング
      matching_albums = line_albums.select { |la| matches_album?(la, album) }
      Rails.logger.info "条件に一致するアルバム: #{matching_albums.size}件"

      if matching_albums.empty?
        Rails.logger.info '条件に一致するアルバムが見つかりませんでした'
        return false
      end

      line_album = if matching_albums.size == 1
                     Rails.logger.info '条件に一致するアルバムが1件見つかりました'
                     matching_albums.first
                   else
                     Rails.logger.info '複数の候補から名前が一致するアルバムを探しています'
                     matching_albums.find { |la| la.album_title.include?(album.name) } || matching_albums.first
                   end

      if line_album
        Rails.logger.info "一致するアルバムが見つかりました: #{line_album.album_title}"
        LineMusicAlbum.save_album(album.album_id, line_album)
        return true
      end
    end

    false
  end
  # rubocop:enable Naming/PredicateMethod

  # アルバムがマッチするかどうかを判定するヘルパーメソッド
  def self.matches_album?(line_album, album)
    if track_counts_match?(line_album, album)
      return (
        (title_matches?(line_album.album_title, album.name) && album_identity_matches?(line_album, album)) ||
        (release_date_matches?(line_album, album) && artist_matches?(line_album, album))
      )
    end

    strict_cross_catalog_match?(line_album, album)
  end

  def self.track_counts_match?(line_album, album)
    track_count_difference(line_album, album).zero?
  end

  def self.track_count_difference(line_album, album)
    line_track_count = line_album.track_total_count
    source_track_count = album.total_tracks
    return Float::INFINITY if line_track_count.blank? || source_track_count.blank?

    (line_track_count - source_track_count).abs
  end

  def self.strict_cross_catalog_match?(line_album, album)
    difference = track_count_difference(line_album, album)
    return false unless difference.between?(1, MAX_STRICT_TRACK_COUNT_DIFFERENCE)

    strict_title_matches?(line_album.album_title, album.name) &&
      release_date_difference(line_album, album).zero? &&
      strict_artist_matches?(line_album, album)
  end

  def self.album_identity_matches?(line_album, album)
    release_date_matches?(line_album, album) || artist_matches?(line_album, album)
  end

  def self.release_date_matches?(line_album, album)
    release_date_difference(line_album, album) <= 7
  end

  def self.release_date_difference(line_album, album)
    return Float::INFINITY if line_album.release_date.blank? || album.release_date.blank?

    (line_album.release_date - album.release_date).abs
  end

  def self.artist_matches?(line_album, album)
    line_artist_tokens = artist_tokens(line_album.artists&.map(&:artist_name)&.join(' '))
    expected_artist_tokens = artist_tokens(expected_artist_names(album).join(' '))
    return false if line_artist_tokens.empty? || expected_artist_tokens.empty?

    line_artist_tokens.intersect?(expected_artist_tokens)
  end

  def self.strict_artist_matches?(line_album, album)
    line_artist_name = normalize_text(line_album.artists&.map(&:artist_name)&.join(' '))
    expected_artist_names = expected_artist_names(album).map { |name| normalize_text(name) }

    line_artist_name.present? && expected_artist_names.include?(line_artist_name)
  end

  def self.expected_artist_names(album)
    names = []
    names << album.artist_name if album.respond_to?(:artist_name)
    names << album.album.circle_name if album.respond_to?(:album) && album.album.present?
    names.compact
  end

  def self.artist_tokens(value)
    normalize_text(value)
      .split
      .reject { |token| token.length <= 1 || %w[feat featuring with and the zun].include?(token) }
  end

  def self.title_matches?(line_title, album_title)
    line = normalize_title(line_title)
    album = normalize_title(album_title)
    return false if line.blank? || album.blank?

    line == album || line.include?(album) || album.include?(line)
  end

  def self.strict_title_matches?(line_title, album_title)
    line = normalize_title(line_title)
    album = normalize_title(album_title)

    line.present? && line == album
  end

  def self.normalize_title(value)
    normalize_text(value).delete_suffix(' single').delete_suffix(' ep')
  end

  def self.normalize_text(value)
    value.to_s.unicode_normalize(:nfkc).downcase.gsub(/[^[:alnum:]ぁ-んァ-ン一-龥]+/, ' ').squish
  end

  def self.find_and_save(id, album)
    Rails.logger.info "LINE MUSIC アルバムID検索: #{id}"
    with_retry(max_attempts: 3) do
      line_album = LineMusic::Album.find(id)

      if line_album.nil?
        Rails.logger.warn "LINE MUSIC アルバムが見つかりませんでした: #{id}"
        return false
      end

      Rails.logger.info "LINE MUSIC アルバム取得成功: #{line_album.album_title}"

      Rails.logger.info(
        "一致判定: リリース日差=#{release_date_difference(line_album, album)}日, " \
        "トラック数=#{line_album.track_total_count} vs #{album.total_tracks}, " \
        "タイトル一致=#{title_matches?(line_album.album_title, album.name)}, " \
        "アーティスト一致=#{artist_matches?(line_album, album)}"
      )

      if matches_album?(line_album, album)
        Rails.logger.info 'アルバム情報が一致しました'
        LineMusicAlbum.save_album(album.album_id, line_album)
        return true
      else
        Rails.logger.info 'アルバム情報が一致しませんでした'
      end
      false
    end
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

  # 複数のクエリで検索を行い、一致するアルバムを保存する
  def self.search_and_save_with_queries(search_queries, album)
    with_retry(max_attempts: 3) do
      Rails.logger.info "LINE MUSIC検索クエリ候補: #{search_queries.join(' | ')}"

      search_queries.each_with_index do |query, index|
        Rails.logger.info "検索クエリ #{index + 1}/#{search_queries.size}: #{query}"

        # 検索結果が見つかった場合は早期リターン
        result = search_and_save(query, album)
        if result
          Rails.logger.info "LINE MUSICアルバムが見つかりました: #{query}"
          return result
        end

        # 検索間隔を少し空ける
        sleep 0.5 unless index == search_queries.size - 1
      end

      Rails.logger.warn "すべての検索クエリでLINE MUSICアルバムが見つかりませんでした: #{album.name}"
      false
    end
  end

  def artist_name
    payload['artists']&.map { it['artist_name'] }&.join(' / ')
  end

  def catalog_track_count
    album&.tracks&.size.to_i
  end

  def catalog_track_difference
    line_track_count = total_tracks.to_i
    local_track_count = catalog_track_count
    return nil unless line_track_count.positive? && local_track_count.positive?

    local_track_count - line_track_count
  end

  def catalog_availability_status
    difference = catalog_track_difference
    return :unknown if difference.nil?
    return :shortage if difference.positive?
    return :excess if difference.negative?

    :complete
  end

  def unavailable_track_count
    [catalog_track_difference.to_i, 0].max
  end

  def track_sync_complete?
    total_tracks.to_i.positive? && line_music_tracks.size >= total_tracks.to_i
  end

  def unavailable_catalog_tracks
    return [] unless catalog_availability_status == :shortage && track_sync_complete?

    mapped_track_ids = line_music_tracks.index_by(&:track_id)
    album.tracks.reject { |track| mapped_track_ids.key?(track.id) }
  end

  def image_url
    payload&.dig('image_url').presence
  end
end
