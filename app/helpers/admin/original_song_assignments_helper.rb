# frozen_string_literal: true

module Admin
  module OriginalSongAssignmentsHelper
    def admin_copyable_original_song_assignment_value(resource_config, track, attribute, label:, thumbnail: true)
      value = resource_config.value_for(track, attribute)
      return admin_display_value(resource_config, track, attribute) if value.blank?

      display_value = thumbnail ? admin_display_value(resource_config, track, attribute) : value.to_s
      admin_copyable_original_song_assignment_button(value, label:, content: display_value)
    end

    def admin_copyable_original_song_assignment_button(value, label:, content: value)
      copy_label = t('admin.original_song_assignments.copy_value', label:, value:)
      tag.button(
        content,
        type: 'button',
        class: 'admin-copyable-value',
        title: copy_label,
        aria: { label: copy_label },
        data: {
          action: 'admin-clipboard#copy',
          admin_clipboard_text_value: value.to_s
        }
      )
    end

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

    def admin_original_song_assignment_album_name(album)
      album.spotify_album_name ||
        album.apple_music_album_name ||
        album.ytmusic_album_name ||
        album.line_music_album_name ||
        album.jan_code
    end

    private

    def admin_minimum_track_number(tracks)
      tracks.filter_map(&:track_number).min
    end
  end
end
