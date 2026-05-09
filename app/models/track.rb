# frozen_string_literal: true

class Track < ApplicationRecord
  ORIGINAL_OR_OTHER_TITLES = %w[オリジナル その他].freeze

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
  scope :original_or_other, -> { where(id: original_or_other_track_ids) }
  scope :touhou_arrangements, -> { where.associated(:original_songs).where.not(id: original_or_other_track_ids).distinct }
  scope :is_touhou, -> { where(is_touhou: true) }
  scope :non_touhou, -> { where(is_touhou: false) }
  scope :jan, ->(jan) { where(jan_code: jan) }
  scope :isrc, ->(isrc) { find_by(isrc:) }

  delegate :circle_name, to: :album

  def album_name
    album.spotify_album&.name || album.apple_music_album&.name
  end

  def image_url
    spotify_tracks.first&.image_url || apple_music_tracks.first&.image_url || ytmusic_tracks.first&.image_url || line_music_tracks.first&.image_url || album.image_url
  end

  def name
    spotify_tracks.first&.name || apple_music_tracks.first&.name
  end

  def original_songs_count
    original_songs.size
  end

  def self.original_or_other_track_ids
    TracksOriginalSong
      .joins(:original_song)
      .where(original_songs: { title: ORIGINAL_OR_OTHER_TITLES })
      .select(:track_id)
  end

  def apple_music_track(album)
    apple_music_tracks.find { it.album_id == album.id }
  end

  def line_music_track(album)
    line_music_tracks.find { it.album_id == album.id }
  end

  def spotify_track(album)
    active_spotify_album = album.spotify_album
    spotify_tracks.find { it.album_id == album.id && it.spotify_album_id == active_spotify_album&.id }
  end

  def ytmusic_track(album)
    ytmusic_tracks.find { it.album_id == album.id }
  end
end
