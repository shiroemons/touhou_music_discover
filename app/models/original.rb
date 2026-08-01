# frozen_string_literal: true

class Original < ApplicationRecord
  self.primary_key = :code

  enum :original_type, {
    windows: 'windows',
    pc98: 'pc98',
    zuns_music_collection: 'zuns_music_collection',
    akyus_untouched_score: 'akyus_untouched_score',
    commercial_books: 'commercial_books',
    other: 'other'
  }

  TYPE_LABELS = {
    windows: '01. Windows作品',
    pc98: '02. PC-98作品',
    zuns_music_collection: "03. ZUN's Music Collection",
    akyus_untouched_score: "04. 幺樂団の歴史　～ Akyu's Untouched Score",
    commercial_books: '05. 商業書籍',
    other: '06. その他'
  }.freeze

  has_many :original_songs, -> { order(Arel.sql('original_songs.track_number ASC')) },
           foreign_key: :original_code,
           inverse_of: :original,
           dependent: :destroy

  scope :original_song_non_duplicated, -> { includes(:original_songs).where(original_songs: { is_duplicate: false }) }
end
