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
    '4580547339208' => 'MPREb_CE4fc2sV3Mc'  # A-One - What's the white magic
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
        ytmusic_album.year != album.release_date.year.to_s &&
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
end
