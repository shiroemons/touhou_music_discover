# frozen_string_literal: true

class OriginalSong < ApplicationRecord
  self.primary_key = :code

  has_many :tracks_original_songs, foreign_key: :original_song_code, inverse_of: :original_song, dependent: :destroy
  has_many :tracks, through: :tracks_original_songs
  has_many :apple_music_tracks, through: :tracks
  has_many :spotify_tracks, through: :tracks

  belongs_to :original,
             foreign_key: :original_code,
             primary_key: :code,
             inverse_of: :original_songs

  delegate :title, :short_title, :original_type, :series_order, to: :original, allow_nil: true, prefix: true

  scope :non_duplicated, -> { where(is_duplicate: false) }

  class << self
    # このアプリが読み書きするプレイリストは「名前が原曲名に一致するもの」だけ。
    # 判定基準をここに集約し、読み取り経路と書き込み経路で必ず同じ基準を使う。
    # 重複曲 (is_duplicate) は原曲別プレイリストの対象にしないため除外する。
    def playlist_titles
      non_duplicated.distinct.pluck(:title)
    end

    def playlist_title?(title)
      return false if title.blank?

      non_duplicated.exists?(title:)
    end

    def playlist_code_for(title)
      return nil if title.blank?

      non_duplicated.find_by(title:)&.code
    end

    # プレイリストを一括処理するときに 1 件ずつ引かないための title => code マップ。
    def playlist_code_map
      non_duplicated.pluck(:title, :code).to_h
    end
  end
end
