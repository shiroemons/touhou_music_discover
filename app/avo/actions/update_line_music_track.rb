# frozen_string_literal: true

class UpdateLineMusicTrack < Avo::BaseAction
  self.name = 'Update line music track'
  self.standalone = true
  self.visible = ->(resource:, view:) { view == :index }

  def handle(_args)
    LineMusicAlbum.eager_load(:line_music_tracks).find_each do |line_music_album|
      lm_tracks = LineMusic::Album.tracks(line_music_album.line_music_id)
      line_music_album.line_music_tracks.each do |line_music_track|
        lm_track = lm_tracks.find { _1.track_id == line_music_track.line_music_id }
        next if lm_track.blank?

        line_music_track.update(
          name: lm_track.track_title,
          disc_number: lm_track.disc_number,
          track_number: lm_track.track_number,
          payload: lm_track.as_json
        )
      end
    end
  end
end
