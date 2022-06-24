# frozen_string_literal: true

class Album < ApplicationRecord
  default_scope { order(jan_code: :desc) }
  TOUHOU_MUSIC_LABEL = '東方同人音楽流通'

  has_many :circles_albums, dependent: :destroy
  has_many :circles, through: :circles_albums
  has_many :tracks, foreign_key: :jan_code, primary_key: :jan_code, inverse_of: :album, dependent: :destroy
  has_many :apple_music_tracks, -> { order(Arel.sql('apple_music_tracks.disc_number ASC, apple_music_tracks.track_number ASC')) }, inverse_of: :album, dependent: :destroy
  has_many :line_music_tracks, -> { order(Arel.sql('line_music_tracks.disc_number ASC, line_music_tracks.track_number ASC')) }, inverse_of: :album, dependent: :destroy
  has_many :spotify_tracks, -> { order(Arel.sql('spotify_tracks.disc_number ASC, spotify_tracks.track_number ASC')) }, inverse_of: :album, dependent: :destroy
  has_many :ytmusic_tracks, -> { order(Arel.sql('ytmusic_tracks.track_number ASC')) }, inverse_of: :album, dependent: :destroy

  has_one :apple_music_album, dependent: :destroy
  has_one :spotify_album, dependent: :destroy
  has_one :line_music_album, dependent: :destroy
  has_one :ytmusic_album, dependent: :destroy

  common_columns = %i[name url release_date total_tracks payload]
  delegate :apple_music_id, *common_columns.push(:label), to: :apple_music_album, allow_nil: true, prefix: true
  delegate :spotify_id, *common_columns.push(:label), to: :spotify_album, allow_nil: true, prefix: true
  delegate :line_music_id, *common_columns, to: :line_music_album, allow_nil: true, prefix: true
  delegate :ytmusic_id, *%i[name url total_tracks payload], to: :ytmusic_album, allow_nil: true, prefix: true

  scope :missing_circles, -> { where.missing(:circles) }
  scope :missing_apple_music_album, -> { where.missing(:apple_music_album) }
  scope :missing_spotify_album, -> { where.missing(:spotify_album) }
  scope :missing_line_music_album, -> { where.missing(:line_music_album) }
  scope :missing_ytmusic_album, -> { where.missing(:ytmusic_album) }
  scope :is_touhou, -> { where(is_touhou: true) }
  scope :non_touhou, -> { where(is_touhou: false) }
  scope :jan, ->(jan) { find_by(jan_code: jan) }

  def circle_name
    circles&.map{_1.name}&.join(' / ')
  end
end
