# frozen_string_literal: true

module Admin
  module OriginalSongAssignmentsHelper
    def admin_original_song_assignment_track_number(track)
      active_spotify_track_number = track.spotify_tracks
                                         .select { |spotify_track| spotify_track.spotify_album&.active? }
                                         .filter_map(&:track_number)
                                         .min

      [
        active_spotify_track_number,
        admin_minimum_track_number(track.apple_music_tracks),
        admin_minimum_track_number(track.line_music_tracks),
        admin_minimum_track_number(track.ytmusic_tracks),
        admin_minimum_track_number(track.spotify_tracks)
      ].compact.first
    end

    private

    def admin_minimum_track_number(tracks)
      tracks.filter_map(&:track_number).min
    end
  end
end
