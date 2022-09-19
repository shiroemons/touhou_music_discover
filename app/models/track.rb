# frozen_string_literal: true

class Track < ApplicationRecord
  has_many :tracks_original_songs, dependent: :destroy
  has_many :original_songs, through: :tracks_original_songs

  has_many :apple_music_tracks, dependent: :destroy
  has_many :line_music_tracks, dependent: :destroy
  has_many :spotify_tracks, dependent: :destroy
  has_many :spotify_track_audio_features, dependent: :destroy
  has_many :ytmusic_tracks, dependent: :destroy

  belongs_to :album, foreign_key: :jan_code, primary_key: :jan_code, inverse_of: :tracks

  scope :missing_apple_music_tracks, -> { where.missing(:apple_music_tracks) }
  scope :missing_line_music_tracks, -> { where.missing(:line_music_tracks) }
  scope :missing_spotify_tracks, -> { where.missing(:spotify_tracks) }
  scope :missing_ytmusic_tracks, -> { where.missing(:ytmusic_tracks) }
  scope :missing_original_songs, -> { where.missing(:original_songs) }
  scope :is_touhou, -> { where(is_touhou: true) }
  scope :non_touhou, -> { where(is_touhou: false) }
  scope :jan, ->(jan) { where(jan_code: jan) }
  scope :isrc, ->(isrc) { find_by(isrc:) }

  def apple_music_track(album)
    apple_music_tracks.find { _1.album == album }
  end

  def line_music_track(album)
    line_music_tracks.find { _1.album == album }
  end

  def spotify_track(album)
    spotify_tracks.find { _1.album == album }
  end

  def ytmusic_track(album)
    ytmusic_tracks.find { _1.album == album }
  end
end
