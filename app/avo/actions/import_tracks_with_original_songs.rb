# frozen_string_literal: true

class ImportTracksWithOriginalSongs < Avo::BaseAction
  self.name = 'Import tracks with original songs'
  self.standalone = true
  self.visible = -> { view == :index }

  field :tsv_file, as: :file, accept: 'text/tab-separated-values'

  def handle(**args)
    field = args.values_at(:fields).first

    fail('Import error.') unless field['tsv_file']&.content_type&.in?(['text/tab-separated-values'])

    songs = CSV.table(field['tsv_file'].path, col_sep: "\t", converters: nil, liberal_parsing: true)
    songs.each do |song|
      jan_code = song[:jan_code]
      isrc = song[:isrc]
      original_songs = song[:original_songs]
      track = Track.find_by(jan_code:, isrc:)
      if track.present? && original_songs.present?
        original_song_list = OriginalSong.where(title: original_songs.split('/'), is_duplicate: false)
        track.original_songs = original_song_list
      end
    end
    succeed('Completed!')
    reload
  end
end
