# frozen_string_literal: true

require 'csv'

args = ARGV.reject { it == '--' }
abort "Usage: bin/rails runner scripts/export_ytmusic_album_dates.rb -- FROM_DATE [OUTPUT_PATH]\nExample: bin/rails runner scripts/export_ytmusic_album_dates.rb -- 2026-03-16" unless args.size.between?(1, 2)

from_date = Date.iso8601(args[0])
from_time = from_date.in_time_zone.beginning_of_day
output_path = args[1]&.then { Rails.root.join(it) } || Rails.root.join('tmp', "ytmusic_album_dates_from_#{from_date.iso8601}.csv")

tracks = YtmusicTrack.unscoped
                     .includes(:album, :ytmusic_album)
                     .where(ytmusic_tracks: { created_at: from_time.. })
groups = tracks.group_by(&:ytmusic_album)

headers = %w[
  app_saved_on
  album_name
  artist_name
  browse_id
  album_url
  tracks_saved
  total_tracks
  youtube_registered_dates
  youtube_release_dates
  sample_video_id
  sample_track_name
  sample_track_url
  errors
]

CSV.open(output_path, 'w', write_headers: true, headers:) do |csv|
  groups.sort_by { |album, album_tracks| [album_tracks.map(&:created_at).min, album&.name.to_s] }.each.with_index(1) do |(album, album_tracks), index|
    warn "[#{index}/#{groups.size}] #{album.name}"

    videos = album_tracks.sort_by(&:track_number).filter_map do |track|
      sleep 0.05
      [track, YtMusic::Video.find(track.video_id)]
    rescue StandardError => e
      [track, e]
    end

    errors = videos.filter_map do |track, result|
      next unless result.is_a?(StandardError)

      "#{track.video_id}: #{result.class} #{result.message}"
    end
    metadata = videos.filter_map { |_track, result| result unless result.is_a?(StandardError) }
    sample_track = album_tracks.min_by(&:track_number)

    csv << [
      album_tracks.map(&:created_at).min.to_date.iso8601,
      album.name,
      album.artist_name,
      album.browse_id,
      album.url,
      album_tracks.size,
      album.total_tracks,
      metadata.filter_map { |video| video.publish_date&.iso8601 }.uniq.sort.join(';'),
      metadata.filter_map { |video| video.release_date&.iso8601 }.uniq.sort.join(';'),
      sample_track.video_id,
      sample_track.name,
      sample_track.url,
      errors.join('; ')
    ]
  end
end

puts output_path
