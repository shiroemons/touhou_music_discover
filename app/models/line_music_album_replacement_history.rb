# frozen_string_literal: true

class LineMusicAlbumReplacementHistory < ApplicationRecord
  self.table_name = 'line_music_album_replacements'

  belongs_to :line_music_album

  validates :old_line_music_id, :new_line_music_id, :new_url, :new_total_tracks, presence: true
end
