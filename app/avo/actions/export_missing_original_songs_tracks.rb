# frozen_string_literal: true

class ExportMissingOriginalSongsTracks < Avo::BaseAction
  self.name = 'Export missing original songs tracks'
  self.standalone = true
  self.visible = -> { view == :index }
  self.may_download_file = true

  def handle(_args)
    tsv_data = CSV.generate(col_sep: "\t") do |csv|
      csv << %w[jan_code isrc circle_name album_name track_name original_songs]
      Track.includes(:spotify_tracks, :apple_music_tracks).missing_original_songs.order(jan_code: :desc).order(isrc: :asc).each do |track|
        column_values = [
          track.jan_code,
          track.isrc,
          track.circle_name,
          track.album_name,
          track.name,
          track.original_songs.map(&:title).join('/')
        ]
        csv << column_values
      end
    end

    download tsv_data, 'missing_original_songs_tracks.tsv'
  end
end
