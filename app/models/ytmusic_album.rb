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
    '4582736133666' => 'MPREb_QKaLdYekFWj'  # .new label - ( ੭´ •ω•`)⊃━☆₷₪$₤₦฿₮₫₯₥₰₫₮฿₶∝₯₥
  }.freeze

  def self.save_album(album_id, browse_id, album)
    find_or_create_by!(
      album_id:,
      browse_id:,
      name: album.title,
      url: "https://music.youtube.com/browse/#{browse_id}",
      playlist_url: album.playlist_url,
      total_tracks: album.track_total_count,
      release_year: album.year,
      payload: album.as_json
    )
  end

  def self.search_and_save(query, album)
    response = YTMusic::Album.search(query)
    return false if response.data[:albums].blank?

    ytmusic_albums = response.data[:albums]
    ytm_albums = ytmusic_albums.filter { _1.year == album.release_date.year.to_s }
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

  def self.find_and_save(browse_id, album)
    ytmusic_album = YTMusic::Album.find(browse_id)
    return false if album.total_tracks != ytmusic_album.track_total_count

    save_album(album.album_id, browse_id, ytmusic_album)
    true
  end

  def self.similar_check_and_save(similar, album, ytm_album)
    return false unless similar.average.to_d > BigDecimal('0.80') && similar.jarowinkler_similar.to_d > BigDecimal('0.85')

    ytmusic_album = YTMusic::Album.find(ytm_album.browse_id)
    return false if album.total_tracks != ytmusic_album.track_total_count

    save_album(album.album_id, ytm_album.browse_id, ytmusic_album)
    true
  end

  def update_album(album, url)
    update(
      name: album.title,
      release_year: album.year,
      url:,
      playlist_url: album.playlist_url,
      total_tracks: album.track_total_count,
      payload: album.as_json
    )
  end

  def artist_name
    payload&.dig('artists')&.map { _1['name'] }&.join(' / ')
  end

  def image_url
    payload&.dig('thumbnails', -1, 'url')&.sub(/=w.*\z/, '')
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[album_id browse_id name payload playlist_url release_year total_tracks url]
  end

  def self.fetch_albums
    Album.includes(:spotify_album, :apple_music_album).missing_ytmusic_album.order(:jan_code).find_each do |album|
      sleep(0.2) # API呼び出し等のレート制限に配慮
      process_album_with_spotify(album)
      process_album_with_apple_music(album) if album.apple_music_album.present?
    end

    update_ytmusic_album_urls
  end

  def self.process_album_with_spotify(album)
    s_album = album.spotify_album
    return if s_album.blank?

    browse_id = JAN_TO_ALBUM_BROWSE_IDS[album.jan_code]
    return if browse_id && find_and_save(browse_id, s_album)

    spotify_artist_names = s_album.payload['artists'].filter { _1['name'] != 'ZUN' }.map { _1['name'] }.join(' ')
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

    search_queries = []
    queries.each do |name, names|
      search_queries << "#{name} #{names}".strip
    end

    search_queries.uniq!
    search_queries.each do |query|
      Rails.logger.debug { "Query: #{query}" }
      return if search_and_save(query, s_album)
    end
  end

  def self.update_ytmusic_album_urls
    ytmusic_album_ids = where(url: nil).pluck(:id)
    batch_size = 1000
    ytmusic_album_ids.each_slice(batch_size) do |ids|
      where(id: ids).then do |records|
        Parallel.each(records, in_processes: 7) do |ytmusic_album|
          album = YTMusic::Album.find(ytmusic_album.browse_id)
          url = "https://music.youtube.com/browse/#{ytmusic_album.browse_id}"
          ytmusic_album.update_album(album, url) if album
        end
      end
    end
  end
end
