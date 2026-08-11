# frozen_string_literal: true

module Admin
  module OriginalSongAssignmentsHelper
    def admin_copyable_original_song_assignment_value(resource_config, track, attribute, label:, thumbnail: true)
      value = resource_config.value_for(track, attribute)
      return admin_display_value(resource_config, track, attribute) if value.blank?

      display_value = thumbnail ? admin_display_value(resource_config, track, attribute) : value.to_s
      admin_copyable_original_song_assignment_button(value, label:, content: display_value)
    end

    def admin_copyable_original_song_assignment_resolved_value(value, label:, display_value: value)
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
      album.display_name
    end

    def admin_original_song_assignment_title_source_badge(resolution)
      source_label = t("admin.values.album_title_source.#{resolution&.source || 'unavailable'}", default: t('admin.values.album_title_source.unavailable'))
      mode = if resolution&.override?
               'override'
             elsif resolution&.fallback?
               'fallback'
             else
               'automatic'
             end
      mode_label = t("admin.values.album_title_source_mode.#{mode}")
      title = if resolution
                current, total = resolution.coverage
                t('admin.original_song_assignments.title_source_coverage', current:, total:)
              end

      tag.span("#{source_label}・#{mode_label}", class: %w[badge admin-title-source-badge], title:)
    end

    def admin_original_song_assignment_track_title_resolution(track, title_resolutions)
      title_resolutions&.fetch(track.jan_code, nil) || track.album&.display_title_resolution
    end

    private

    def admin_minimum_track_number(tracks)
      tracks.filter_map(&:track_number).min
    end
  end
end
