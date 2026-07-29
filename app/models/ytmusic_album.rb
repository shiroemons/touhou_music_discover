# frozen_string_literal: true

class YtmusicAlbum < ApplicationRecord
  default_scope { includes(:album).order('albums.jan_code desc') }

  has_many :ytmusic_tracks,
           -> { order(Arel.sql('ytmusic_tracks.track_number ASC')) },
           inverse_of: :ytmusic_album,
           dependent: :destroy

  belongs_to :album

  delegate :jan_code, :is_touhou, :circle_name, to: :album, allow_nil: true

  scope :is_touhou, -> { eager_load(:album).where(albums: { is_touhou: true }) }
  scope :non_touhou, -> { eager_load(:album).where(albums: { is_touhou: false }) }
  scope :browse_id, ->(browse_id) { find_by(browse_id:) }
  # distributed_onが未確定、前回の集計がfailedだった行に加え、distribution_track_metadataに
  # 縮退した動画（degraded: true）が1件でも残っている行も対象にする。縮退が一部だけのアルバムは
  # distributed_onが算出済みでも、不完全なデータから算出した配信日が固定化されてしまうため。
  scope :distribution_missing, lambda {
    where(
      "distributed_on IS NULL OR distribution_source = 'failed' OR " \
      "distribution_track_metadata @> '[{\"degraded\": true}]'"
    )
  }

  # 検索で見つけにくいアルバム
  # コメントアウトしているアルバムは、YouTubeMusicで配信されていないアルバム
  JAN_TO_ALBUM_BROWSE_IDS = {
    '4580547310795' => 'MPREb_eeAHV4hJikZ', # IOSYS - ファンタジックぴこれーしょん! [東方ProjectアレンジSelection]
    '4580547315028' => 'MPREb_3LbKcm9Blf0', # SOUND HOLIC - 幻想★あ･ら･もーど
    '4580547315783' => 'MPREb_mTu9AJ0IMQS', # Blackscreen/t0m0h1r0/beth_tear/矢追春樹 - Parallels
    '4580547318647' => 'MPREb_N0ObSy2IBoB',	# 彩音 〜xi-on〜 - Quartet -カルテット-
    '4580547320978' => 'MPREb_YWnLG9wPJbM', # しもしゃん(MICMNIS) - Event Horizon
    #    '4580547331653' => '',	# Amateras Records - 恋繋エピローグ
    #    '4580547331783' => '',	# EastNewSound - Lyrical Crimson
    #    '4580547311440' => '',	# 豚乙女 - 東方猫鍵盤9
    '4580547319644' => 'MPREb_UGZhVAD5vCt',	# ヴァリアス・アーティスト - Edge
    #    '4580547331646' => '',	# Amateras Records - Amateras Records Extended Selection Vol.2
    '4580547321616' => 'MPREb_k6psJBn5ano',	# ZYTOKINE - Ћ⊿⊿θ▽△
    '4580547327571' => 'MPREb_KVu5QJe1rZh', # 幽閉サテライト - 色は匂へど 散りぬるを (BAND arrange version vol.1)
    '4580547334661' => 'MPREb_jcbfEMq2FSt', # 幽閉サテライト - 色は匂へど散りぬるを BAND arrange version vol.1
    '4580547337068' => 'MPREb_BIzpXNML9zZ', # K2E†Cradle - TOHO EURO TRIGGER VOL.17 Non-Stop BEST
    '4580547337150' => 'MPREb_Bi4eL7O8d2W', # SOUND HOLIC - EUROBEAT HOLIC III -SEPARATED EDITION-
    '4580547337266' => 'MPREb_ledPRnZolOY', # 上海アリス幻樂団 - 虹色のセプテントリオン
    '4580547337693' => 'MPREb_r2gBqTAcOl7', # 魂音泉 - Lu○Na
    '4580547337709' => 'MPREb_6q8Ngwz42zE', # 魂音泉 - Lu○Na -eclipse-
    '4580547337907' => 'MPREb_MD7iqNzhx9G', # Dドライブ - -10400000k
    '4580547339109' => 'MPREb_7m49E8zKaBH', # Astral Sky、非可逆リズム - SUPERNOV∀
    '4580547338638' => 'MPREb_oygvl00mVC5', # A-One - U.N. Owen Was Her? feat. HIKO
    '4580547339161' => 'MPREb_p7J6QrGPW2W', # A-One - What's the white magic（feat. lily-an）
    '4580547339208' => 'MPREb_CE4fc2sV3Mc', # A-One - What's the white magic
    '4582736130665' => 'MPREb_JH8ScoLuuR8', # COOL&CREATE - Help me, ERINNNNNN!! (～たすけてえーりん!!～) [feat. 初音ミク]
    '4582736130658' => 'MPREb_cnPmw96cCjF', # COOL&CREATE - Help me, ERINNNNNN!! (～たすけてえーりん!!～)
    '4582736130344' => 'MPREb_Q9ZBcfoRVzn', # 東方LostWord - 刻の境界 feat.いとうかなこ×東京アクティブNEETs
    '4582736130351' => 'MPREb_t91yIcLUOL2', # 東方LostWord - PHANTOM PAIN feat.KOTOKO×ZYTOKINE
    '4582736130368' => 'MPREb_HBkwY3WaipO', # 東方LostWord - Be the change feat.大坪由佳×DiGiTAL WiNG
    '4582736130375' => 'MPREb_DIQH9nxXAtf', # 東方LostWord - 月、想ふ時 feat.宮村優子×幽閉サテライト
    '4582736130382' => 'MPREb_9iyV9K8e5P0', # 東方LostWord - タタエロスト feat.岸田メル×石鹸屋
    '4582736130399' => 'MPREb_YoBnANz3ocb', # 東方LostWord - ナシミのデグチ feat.榎本温子×はにーぽけっと
    '4582736130405' => 'MPREb_tRx3JKkZLVm', # 東方LostWord - (TT)プレシャスワード feat.桃井はるこ×IOSYS
    '4582736130412' => 'MPREb_fXttSxGXJj0', # 東方LostWord - 命に名前をつけるなら feat.渕上舞×少女理論観測所
    '4582736130429' => 'MPREb_6vsGYW7ehPy', # 東方LostWord - Holy Again feat.Teresa×発熱巫女～ず
    '4582736130436' => 'MPREb_Z8xryUnkOby', # 東方LostWord - 感傷のシグナル feat.花守ゆみり×東方事変
    '4582736130443' => 'MPREb_tL0wx5vVUlj', # 東方LostWord - 追想の愛 feat.大槻ケンヂ×豚乙女
    '4582736130450' => 'MPREb_kfT1GYMCGg1', # 東方LostWord - 世界一位 feat.徳井青空×Alstroemeria Records
    '4582736130627' => 'MPREb_iEdWKdsLr40', # 凋叶棕 - Ｑ（愛蔵版）
    '4582736131082' => 'MPREb_vPJVoQJ3PrA', # ガネメ - Chu♡Chu♡Chu
    '4582736133666' => 'MPREb_QKaLdYekFWj', # .new label - ( ੭´ •ω•`)⊃━☆₷₪$₤₦฿₮₫₯₥₰₫₮฿₶∝₯₥
    '4582736134021' => 'MPREb_qfkiNe55GcX', # 非可逆リズム - 妖魔夜行 (MRM REMIX) feat. モリモリあつし
    '4582736134007' => 'MPREb_qkhRjC18qsZ', # 非可逆リズム - 満月の竹林 (MRM REMIX) feat. モリモリあつし
    '4582736133987' => 'MPREb_twy0YQaTUy6', # 非可逆リズム - 遠野幻想物語 (MRM REMIX) feat. モリモリあつし
    '4582736133970' => 'MPREb_CgG1tmhnQz8', # 非可逆リズム - パリピフラン feat. モリモリあつし
    '4582736133932' => 'MPREb_8rF6ZB4kmJd', # 非可逆リズム - LIMIT BURST (GC Mix.) feat. adaptor, モリモリあつし
    '4582736134557' => 'MPREb_Skha7QKftQu', # fractrick - Eyed(Single)
    '4582736134755' => 'MPREb_IUioqK8ltkL', # .new label - -80538738812075974³+80435758145817515³+12602123297335631³
    '4582736136209' => 'MPREb_4xbd6llVTwu', # 東方LostWord - 欠損Ride on (feat. 藤咲凪 from 最終未来少女 × 豚乙女)
    '4582736136247' => 'MPREb_YmBDqjVTnpN', # 東方LostWord - 承認欲求☆あんのんがーる (feat. 野田真理愛 × 少女理論観測所)
    '4582736136254' => 'MPREb_NPWhgfTHuBG', # 東方LostWord - ドキワク❄︎レボリューション（feat. May’n、豚乙女）
    '4582736136780' => 'MPREb_6CPOXTh82vP', # 発熱巫女〜ず - Knocked on the Door
    '4582736136810' => 'MPREb_Ofa96OUBxIl', # 幽閉サテライト - 漢の幽閉サテライトEX
    '4582736136957' => 'MPREb_GzesQoATD9B', # Amateras Records - Stray Star (Overhead Champion Remix)
    '4582736136964' => 'MPREb_2gsuF3PU4Km', # Bullet IX - Soul Igniter
    '4582736137107' => 'MPREb_XVnaMc5BujE', # Further Ahead Of Warp - Looking For The Me No One Knows
    '4582736137114' => 'MPREb_aOsC78GNNNj', # KALANCHOE RECORDS - Oblivion Feast
    '4582736137206' => 'MPREb_ISpVdCDrQq1', # .new label - ?¿!?!¿!!?¿?¿!!!!
    '4582736137305' => 'MPREb_oTEG5HlOnxU', # イノライ - 地上の兎は星になる
    '4582736137329' => 'MPREb_u4U3MWe3cD8', # イノライ - STARDUST
    # '4582736137428' => '', # 激戦魂 -Gekisen Soul- - GEKISTAR
    '4582736137503' => 'MPREb_7rkSN3YNR4U', # 染色硝子ノ欠片 - 絶対零度の六花
    '4582736137800' => 'MPREb_bPACsUquwVB', # イノライ - Valentine Mode♡
    '4582736137589' => 'MPREb_Db20SEqtUq8', # Amateras Records - Endless Journey
    '4582736137572' => 'MPREb_oW3jQYYowoE', # Amateras Records - 恋トラ -KOIIRO MASTER TRANCE 04-
    '4582736137664' => 'MPREb_Hldch6TUzZL'  # Moonlight Magic - Coldblood
  }.freeze

  def self.save_album(album_id, browse_id, album)
    if album.degraded?
      Rails.logger.warn "browse_id: #{browse_id} の取得結果が縮退しているため保存をスキップしました"
      return nil
    end

    ytmusic_album = find_or_create_by!(album_id:, browse_id:) do |record|
      record.name = album.title
    end

    ytmusic_album.update_album(album, "https://music.youtube.com/browse/#{browse_id}")
    ytmusic_album
  end

  def self.search_and_save(query, album)
    response = YtMusic::Album.search(query)
    return false if response.data[:albums].blank?

    ytmusic_albums = response.data[:albums]
    ytm_albums = if album.release_date
                   ytmusic_albums.filter { it.year == album.release_date.year.to_s }
                 else
                   ytmusic_albums
                 end
    return false if ytm_albums.empty?

    if album.is_a?(SpotifyAlbum)
      ytm_albums.each do |ytm_album|
        return find_and_save(ytm_album.browse_id, album) if ytm_album.title == album.name && album.payload['artists'].map { |artist| artist['name'] }.join(' ')
      end
    end

    ytm_albums.each do |ytm_album|
      if album.name.unicode_normalize.include?('【睡眠用】東方ピアノ癒やし子守唄')
        album_name = album.name.unicode_normalize.sub(/\(.*\z/, '').tr('０-９', '0-9').strip
        ytm_album_title = ytm_album.title.unicode_normalize.sub(/\(.*\z/, '').tr('０-９', '0-9').strip
        next if album_name != ytm_album_title

        similar = Similar.new(album_name, ytm_album_title)
        return true if similar_check_and_save(similar, album, ytm_album)
      end

      album_name = album.name.unicode_normalize
                        .gsub(/\p{In_Halfwidth_and_Fullwidth_Forms}+/) { |str| str.unicode_normalize(:nfkd) }
                        .gsub(/[(|（\[].*[)|）\]]/, '').delete_suffix(' - EP')
                        .tr('０-９', '0-9').strip
      ytm_album_title = ytm_album.title.unicode_normalize
                                 .gsub(/\p{In_Halfwidth_and_Fullwidth_Forms}+/) { |str| str.unicode_normalize(:nfkd) }
                                 .gsub(/[(|（\[].*[)|）\]]/, '')
                                 .tr('０-９', '0-9').strip
      similar = Similar.new(album_name, ytm_album_title)
      return true if similar_check_and_save(similar, album, ytm_album)
    end

    ytm_album = ytmusic_albums.find do |ytmusic_album|
      ytmusic_album.title == album.name &&
        ytmusic_album.year == album.release_date.year.to_s &&
        ytmusic_album.artists.map(&:name).join(' / ') == album.artist_name
    end

    return find_and_save(ytm_album.browse_id, album) if ytm_album

    false
  end

  # rubocop:disable Naming/PredicateMethod
  def self.find_and_save(browse_id, album)
    ytmusic_album = YtMusic::Album.find(browse_id)
    return false if ytmusic_album.nil? || album.total_tracks != ytmusic_album.track_total_count
    return false if album.release_date && ytmusic_album.year.present? && album.release_date.year.to_s != ytmusic_album.year

    save_album(album.album_id, browse_id, ytmusic_album).present?
  end
  # rubocop:enable Naming/PredicateMethod

  # rubocop:disable Naming/PredicateMethod
  def self.similar_check_and_save(similar, album, ytm_album)
    return false unless similar.average.to_d > BigDecimal('0.80') && similar.jarowinkler_similar.to_d > BigDecimal('0.85')

    ytmusic_album = YtMusic::Album.find(ytm_album.browse_id)
    return false if ytmusic_album.nil? || album.total_tracks != ytmusic_album.track_total_count

    save_album(album.album_id, ytm_album.browse_id, ytmusic_album).present?
  end
  # rubocop:enable Naming/PredicateMethod

  def update_album(album, url)
    if album.degraded?
      Rails.logger.warn "YtmusicAlbum##{id} (browse_id: #{browse_id}) の取得結果が縮退しているためpayload更新をスキップしました"
      return false
    end

    existing_count = existing_playable_track_count
    if existing_count.positive? && album.playable_track_count < existing_count
      Rails.logger.warn "YtmusicAlbum##{id} (browse_id: #{browse_id}) の取得結果は既存 #{existing_count} 件 → 取得 #{album.playable_track_count} 件 で悪化するためpayload更新をスキップしました"
      return false
    end

    update(
      name: album.title,
      release_year: album.year,
      url:,
      playlist_url: album.playlist_url,
      total_tracks: album.track_total_count,
      payload: album.as_json
    )
  end

  # 配信日を集計し直す。HTTPは行わず、DB上に保存済みのデータのみで完結する。
  # distribution_track_metadataが保存されていればそれを正として使う（ytmusic_tracksの行は
  # アルバム取り込みより遅れて作られるため、行が無い/一部しか無いアルバムでも集計できるようにするため）。
  # 保存されていなければ従来どおりytmusic_tracksの行から集計する（後方互換）。
  def recalculate_distribution!
    tracks, source_of_truth = distribution_tracks_for_calculation
    result = DistributionCalculator.new(tracks, source_of_truth:).call

    update!(
      distributed_on: result.distributed_on,
      youtube_published_on: result.youtube_published_on,
      original_released_on: result.original_released_on,
      distribution_source: result.distribution_source,
      distribution_stats: result.distribution_stats,
      distribution_fetched_at: Time.current
    )
  end

  def artist_name
    payload&.dig('artists')&.map { it['name'] }&.join(' / ')
  end

  def image_url
    payload&.dig('thumbnails', -1, 'url')&.sub(/=w.*\z/, '')
  end

  def self.fetch_albums(progress_callback: nil)
    albums = Album.includes(:spotify_album, :apple_music_album).missing_ytmusic_album.order(:jan_code)
    total_count = albums.count
    stats = {
      target_albums: total_count,
      acquired_albums: 0,
      not_found_albums: 0,
      errors: 0,
      error_examples: []
    }
    progress_callback&.call(
      current: 0,
      total: total_count,
      message: 'YouTube Musicアルバム候補を処理しています',
      reset: true
    )

    albums.find_each.with_index(1) do |album, index|
      sleep(0.2) # API呼び出し等のレート制限に配慮
      progress_callback&.call(
        current: index - 1,
        total: total_count,
        message: "YouTube Musicアルバム候補を処理中: #{index}/#{total_count} #{album.jan_code}"
      )

      outcome = begin
        process_album_with_spotify(album)
        process_album_with_apple_music(album) if album.apple_music_album.present? && !unscoped.exists?(album_id: album.id)

        if unscoped.exists?(album_id: album.id)
          stats[:acquired_albums] += 1
          '取得'
        else
          stats[:not_found_albums] += 1
          '未検出'
        end
      rescue StandardError => e
        stats[:errors] += 1
        stats[:error_examples] << "#{album.jan_code}: #{e.message}"
        Rails.logger.error(
          "[YtmusicAlbum] album fetch failed for JAN #{album.jan_code}: #{e.class} - #{e.message}"
        )
        "エラー (#{e.class})"
      end

      progress_callback&.call(
        current: index,
        total: total_count,
        message: "YouTube Musicアルバム候補: #{index}/#{total_count} #{album.jan_code} #{outcome} " \
                 "(取得#{stats[:acquired_albums]}件 / 未検出#{stats[:not_found_albums]}件 / エラー#{stats[:errors]}件)"
      )
    end

    update_ytmusic_album_urls(progress_callback:)
    stats
  end

  def self.process_jan_to_album_browse_ids
    result = { created: 0, skipped: 0, errors: 0, missing: 0 }
    Admin::ActionProgress.start(total: JAN_TO_ALBUM_BROWSE_IDS.size, message: 'JAN_TO_ALBUM_BROWSE_IDS を処理しています')

    JAN_TO_ALBUM_BROWSE_IDS.each do |jan_code, browse_id|
      album = Album.find_by(jan_code:)

      if album.nil?
        result[:missing] += 1
        Rails.logger.warn "JAN: #{jan_code} のアルバムが見つかりません"
        Admin::ActionProgress.advance(message: "JANを処理しています: #{jan_code}")
        next
      end

      if album.ytmusic_album.present? || YtmusicAlbum.exists?(browse_id:)
        result[:skipped] += 1
        Admin::ActionProgress.advance(message: "JANを処理しています: #{jan_code}")
        next
      end

      begin
        ytmusic_album = YtMusic::Album.find(browse_id)

        if ytmusic_album.blank?
          result[:errors] += 1
          Rails.logger.warn "エラー: JAN #{jan_code} - YouTube Music アルバムが見つかりません: #{browse_id}"
          next
        end

        save_album(album.id, browse_id, ytmusic_album)
        result[:created] += 1
        Rails.logger.info "作成: JAN #{jan_code} → YouTube Music browse ID #{browse_id}"
      rescue StandardError => e
        result[:errors] += 1
        Rails.logger.error "エラー: JAN #{jan_code} - #{e.class}: #{e.message}"
      ensure
        Admin::ActionProgress.advance(message: "JANを処理しています: #{jan_code}") if album.present?
      end
    end

    result
  end

  def self.process_album_with_spotify(album)
    s_album = album.spotify_album
    return if s_album.blank?

    browse_id = JAN_TO_ALBUM_BROWSE_IDS[album.jan_code]
    return if browse_id && find_and_save(browse_id, s_album)

    spotify_artist_names = s_album.payload['artists'].filter { it['name'] != 'ZUN' }.map { it['name'] }.join(' ')
    normalize_and_search_ytmusic(s_album, spotify_artist_names)
  end

  def self.process_album_with_apple_music(album)
    am_album = album.apple_music_album
    am_album_name = am_album.name.gsub(/(-|─|☆|■|≒|⇔)/, '')
    artist_name = am_album.artist_name
    query = "#{am_album_name} #{artist_name}"
    return if search_and_save(query, am_album)

    # Apple Musicアルバム名の様々なバリエーションで検索
    [am_album_name, am_album_name.sub(/ [(|\[].*[)|\]]\z/, ''), am_album.name, am_album.name.sub(' - EP', '').sub(' - Single', '')].each do |q|
      return if search_and_save(q, am_album)
    end

    search_songs_and_save(am_album)
  end

  def self.normalize_and_search_ytmusic(s_album, artist_names)
    queries = [
      [s_album.name.unicode_normalize, artist_names],
      [s_album.name.unicode_normalize.gsub(/( -|─|☆|■|≒|⇔)/, ' ')
              .gsub(/\p{In_Halfwidth_and_Fullwidth_Forms}+/) { |str| str.unicode_normalize(:nfkd) }
              .gsub(/ [(|（\[].*[)|）\]]/, '')
              .tr('０-９', '0-9').strip, artist_names]
    ]
    queries << [s_album.name, ''] if s_album.name.unicode_normalize.include?('【睡眠用】東方ピアノ癒やし子守唄')

    search_queries = queries.map do |name, names|
      "#{name} #{names}".strip
    end

    search_queries.uniq!
    search_queries.each do |query|
      Rails.logger.debug { "Query: #{query}" }
      return if search_and_save(query, s_album)
    end

    search_songs_and_save(s_album)
  end

  # YouTube Musicではシングルがアーティストページの「シングルと EP」や曲検索には出る一方、
  # albumsフィルター付き検索に返らないことがある。曲検索のメタデータに含まれるアルバムbrowse IDを
  # たどり、リリース年・曲数をfind_and_saveで再検証してから保存する。
  # rubocop:disable Naming/PredicateMethod
  def self.search_songs_and_save(source_album)
    source_tracks(source_album).first(3).each do |source_track|
      song_search_queries(source_album, source_track).each do |query|
        Rails.logger.debug { "Song Query: #{query}" }
        songs = YtMusic::Album.search_songs(query).data[:songs]
        Array(songs).each do |song|
          next if song.album_browse_id.blank?
          next unless matching_source_song?(song, source_album, source_track)

          return true if find_and_save(song.album_browse_id, source_album)
        end
      end
    end

    false
  end
  # rubocop:enable Naming/PredicateMethod

  def self.source_tracks(source_album)
    return source_album.spotify_tracks if source_album.respond_to?(:spotify_tracks)
    return source_album.apple_music_tracks if source_album.respond_to?(:apple_music_tracks)

    []
  end

  def self.song_search_queries(source_album, source_track)
    base_title = normalized_ytmusic_title(source_track.name)
    artist_names = [source_album.artist_name, *source_track_artist_names(source_track)].compact_blank

    [
      *artist_names.map { |artist_name| "#{base_title} #{artist_name}" },
      base_title
    ].uniq
  end

  def self.matching_source_song?(song, source_album, source_track)
    title_matches = normalized_ytmusic_title(song.title) == normalized_ytmusic_title(source_track.name)
    return false unless title_matches

    album_title_matches = normalized_ytmusic_title(song.album_title) == normalized_ytmusic_title(source_album.name)
    source_artists = [source_album.artist_name, *source_track_artist_names(source_track)]
                     .compact_blank
                     .map { normalize_ytmusic_text(it) }
    song_artists = song.artists.map { normalize_ytmusic_text(it.name) }

    album_title_matches || source_artists.intersect?(song_artists)
  end

  def self.source_track_artist_names(source_track)
    payload_artists = Array(source_track.payload&.fetch('artists', nil)).filter_map { it['name'] }
    [*payload_artists, source_track.try(:artist_name)].compact_blank
  end

  def self.normalized_ytmusic_title(title)
    normalize_ytmusic_text(title)
      .sub(/\s*[-–—]\s*(?:single|ep)\z/i, '')
      .sub(/\s*[(（]\s*feat\..*[)）]\s*\z/i, '')
      .strip
  end

  def self.normalize_ytmusic_text(text)
    text.to_s.unicode_normalize(:nfkc).downcase.strip
  end

  def self.update_ytmusic_album_urls(progress_callback: nil)
    ytmusic_album_ids = where(url: nil).pluck(:id)
    batch_size = 1000
    total_count = ytmusic_album_ids.size
    return if total_count.zero?

    progress_callback&.call(
      current: 0,
      total: total_count,
      message: 'YouTube MusicアルバムURLを更新しています',
      reset: true
    )

    processed_count = 0
    ytmusic_album_ids.each_slice(batch_size) do |ids|
      finish_callback = lambda do |_ytmusic_album, _index, _result|
        processed_count += 1
        progress_callback&.call(
          current: processed_count,
          total: total_count,
          message: "YouTube MusicアルバムURLを更新しています: #{processed_count}/#{total_count}"
        )
      end

      where(id: ids).then do |records|
        ParallelRunner.each(records, workers: :ytmusic, finish: finish_callback) do |ytmusic_album|
          album = YtMusic::Album.find(ytmusic_album.browse_id)
          url = "https://music.youtube.com/browse/#{ytmusic_album.browse_id}"
          ytmusic_album.update_album(album, url) if album
        end
      end
    end
  end

  private

  # recalculate_distribution!が集計対象にするトラック相当のオブジェクト一覧と、その集計元を返す。
  def distribution_tracks_for_calculation
    if distribution_track_metadata.present?
      [DistributionTrackMetadataRecord.from_metadata(distribution_track_metadata), 'payload']
    else
      [YtmusicTrack.unscoped.where(ytmusic_album_id: id).to_a, 'track_rows']
    end
  end

  # 既存payload中の「video_idが非nilかつtrack_numberが正の整数」であるトラック数。
  # 既存payloadが無い/tracksが空の場合は0を返す（回帰ガードは0件からの改善を常に許可するため）。
  def existing_playable_track_count
    tracks = payload&.dig('tracks')
    return 0 unless tracks.is_a?(Array)

    tracks.count { |track| track['video_id'].present? && track['track_number'].to_i.positive? }
  end
end
