# frozen_string_literal: true

class LineMusicAlbumReplacementCandidate < ApplicationRecord
  STATUSES = %w[pending applied rejected].freeze

  belongs_to :line_music_album

  scope :pending, -> { where(status: 'pending') }

  validates :line_music_id, :name, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :line_music_id, uniqueness: { scope: :line_music_album_id }

  def self.record_from_api!(line_music_album:, line_album:)
    return if line_music_album.blank? || line_album.blank? || line_album.album_id.blank?
    return if line_music_album.line_music_id == line_album.album_id

    candidate = find_or_initialize_by(
      line_music_album_id: line_music_album.id,
      line_music_id: line_album.album_id
    )
    candidate.assign_attributes(
      name: line_album.album_title.presence || '(名称なし)',
      url: LineMusicAlbum.default_url(line_album.album_id),
      release_date: line_album.release_date,
      total_tracks: line_album.track_total_count,
      payload: line_album.as_json
    )
    candidate.status = 'pending' if candidate.new_record?
    candidate.save!
    candidate
  end

  def pending?
    status == 'pending'
  end
end
