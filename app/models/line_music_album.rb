# frozen_string_literal: true

class LineMusicAlbum < ApplicationRecord
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
    '4580547338485' => 'mb0000000002e9d62c'  # 幽閉サテライト - 彩-IRODORI-Singles Best vol.8～穢れなきユーフォリア～
  }.freeze

  # LineMusicのアルバム情報を保存する
  def self.save_album(album_id, lm_album)
    url = "https://music.line.me/webapp/album/#{lm_album.album_id}"

    line_music_album = ::LineMusicAlbum.find_or_create_by!(
      album_id:,
      line_music_id: lm_album.album_id,
      name: lm_album.album_title,
      url:,
      release_date: lm_album.release_date,
      total_tracks: lm_album.track_total_count
    )
    line_music_album.update(payload: lm_album.as_json)
  end

  def self.search_and_save(query, album)
    line_albums = LineMusic::Album.search(query)

    case line_albums.total
    when 0
      return false
    when 1
      line_album = line_albums.find do |la|
        la.release_date == album.release_date && la.track_total_count == album.total_tracks
      end
      line_album ||= line_albums.find do |la|
        la.album_title == album.name && la.track_total_count == album.total_tracks
      end

      if line_album
        LineMusicAlbum.save_album(album.album_id, line_album)
        return true
      end
    else
      line_albums = line_albums.select do |la|
        la.release_date == album.release_date && la.track_total_count == album.total_tracks
      end

      return false if line_albums.empty?

      line_album = if line_albums.size == 1
                     line_albums.first
                   else
                     line_albums.find { _1.album_title.include?(album.name) }
                   end

      if line_album
        LineMusicAlbum.save_album(album.album_id, line_album)
        return true
      end
    end

    false
  end

  def self.find_and_save(id, album)
    line_album = LineMusic::Album.find(id)
    if line_album.release_date == album.release_date && line_album.track_total_count == album.total_tracks
      LineMusicAlbum.save_album(album.album_id, line_album)
      return true
    end
    false
  end

  def artist_name
    payload['artists']&.map { _1['artist_name'] }&.join(' / ')
  end

  def image_url
    payload&.dig('image_url').presence
  end
end
