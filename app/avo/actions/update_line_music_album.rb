# frozen_string_literal: true

class UpdateLineMusicAlbum < Avo::BaseAction
  self.name = 'Update line music album'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    LineMusicAlbum.find_each do |line_music_album|
      lm_album = LineMusic::Album.find(line_music_album.line_music_id)
      if lm_album.present?
        line_music_album.update(
          name: lm_album.album_title,
          total_tracks: lm_album.track_total_count,
          payload: lm_album.as_json
        )
      end
    end
  end
end
