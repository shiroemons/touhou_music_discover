# frozen_string_literal: true

class LineMusicTrack < ApplicationRecord
  default_scope { includes(:album).order('albums.jan_code desc').order(disc_number: :asc).order(track_number: :asc) }

  belongs_to :album
  belongs_to :line_music_album
  belongs_to :track

  delegate :jan_code, :is_touhou, :circle_name, to: :album, allow_nil: true
  delegate :isrc, :is_touhou, to: :track, allow_nil: true
  delegate :image_url, to: :line_music_album, allow_nil: true

  scope :line_music_id, ->(line_music_id) { find_by(line_music_id:) }
  scope :album_line_music_id, ->(line_music_id) { eager_load(:line_music_album).where(line_music_album: { line_music_id: }) }
  scope :is_touhou, -> { eager_load(:track).where(tracks: { is_touhou: true }) }
  scope :non_touhou, -> { eager_load(:track).where(tracks: { is_touhou: false }) }

  def self.fetch_tracks
    album_ids = Album.pluck(:id)
    batch_size = 1000
    album_ids.each_slice(batch_size) do |ids|
      Album.includes(:spotify_album, :apple_music_album, :line_music_album).where(id: ids).then do |records|
        Parallel.each(records, in_processes: 7) do |r|
          process_album(r)
        end
      end
    end
  end

  def self.process_album(album)
    return if album.line_music_album.blank?

    lm_album = album.line_music_album
    return if lm_album.total_tracks == lm_album.line_music_tracks.size

    if album.spotify_album.present?
      match_and_save_tracks_for_spotify(album.spotify_album, lm_album)
    elsif album.apple_music_album.present?
      match_and_save_tracks_for_apple_music(album.apple_music_album, lm_album)
    end
  end

  def self.match_and_save_tracks_for_spotify(spotify_album, line_music_album)
    lm_tracks = LineMusic::Album.tracks(line_music_album.line_music_id)
    spotify_album.spotify_tracks.each do |s_track|
      lm_track = lm_tracks.find { |lm| lm.disc_number == s_track.disc_number && lm.track_number == s_track.track_number }
      save_track(s_track.album_id, s_track.track_id, line_music_album, lm_track) if lm_track
    end
  end

  def self.match_and_save_tracks_for_apple_music(apple_music_album, line_music_album)
    lm_tracks = LineMusic::Album.tracks(line_music_album.line_music_id)
    apple_music_album.apple_music_tracks.each do |am_track|
      lm_track = lm_tracks.find { |lm| lm.disc_number == am_track.disc_number && lm.track_number == am_track.track_number }
      save_track(am_track.album_id, am_track.track_id, line_music_album, lm_track) if lm_track
    end
  end

  def self.save_track(album_id, track_id, lm_album, lm_track)
    url = "https://music.line.me/webapp/track/#{lm_track.track_id}"

    line_music_track = ::LineMusicTrack.find_or_create_by!(
      album_id:,
      track_id:,
      line_music_album_id: lm_album.id,
      line_music_id: lm_track.track_id,
      name: lm_track.track_title,
      url:,
      disc_number: lm_track.disc_number,
      track_number: lm_track.track_number
    )
    line_music_track.update(payload: lm_track.as_json)
  end

  def artist_name
    payload['artists']&.map { _1['artist_name'] }&.join(' / ')
  end
end
