# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tempfile'

class LineMusicAlbumAlgoliaExporter
  FILENAME = 'touhou_music_line_music_for_algolia.json'
  DEFAULT_OUTPUT_DIR = 'tmp/algolia'

  Result = Data.define(:path, :record_count)

  class Error < StandardError; end

  def initialize(line_music_album:, output_dir: nil)
    @line_music_album_id = line_music_album.id
    @output_dir = output_dir || ENV.fetch('ALGOLIA_OUTPUT_DIR', DEFAULT_OUTPUT_DIR)
  end

  def export!
    line_music_album = LineMusicAlbum.unscoped.find(@line_music_album_id)
    album = Album.unscoped
                 .includes(
                   :circles,
                   :line_music_album,
                   line_music_tracks: { track: { original_songs: :original } }
                 )
                 .find(line_music_album.album_id)
    rows = LineMusicAlbumsToAlgoliaPresenter.new([album]).as_json
    path = output_path

    write_atomically(path, JSON.pretty_generate(rows))
    Rails.logger.info "LINE MUSIC Algolia出力: #{path} (#{rows.size}件)"
    Result.new(path, rows.size)
  rescue ActiveRecord::RecordNotFound => e
    raise Error, "Algolia出力対象のLINE MUSICアルバムが見つかりません: #{e.message}"
  rescue StandardError => e
    raise e if e.is_a?(Error)

    Rails.logger.error("LINE MUSIC Algolia出力に失敗しました: #{e.class} - #{e.message}")
    raise Error, "LINE MUSICのAlgolia向けJSON出力に失敗しました: #{e.message}"
  end

  private

  def output_path
    directory = Pathname.new(@output_dir.to_s)
    directory = Rails.root.join(directory) unless directory.absolute?
    FileUtils.mkdir_p(directory)
    directory.join(FILENAME)
  end

  def write_atomically(path, contents)
    Tempfile.create([FILENAME.delete_suffix('.json'), '.json'], path.dirname.to_s) do |temporary_file|
      temporary_file.write(contents)
      temporary_file.flush
      temporary_file.fsync
      File.rename(temporary_file.path, path.to_s)
    end
  rescue SystemCallError => e
    raise Error, "出力ファイルを書き込めません: #{path} (#{e.message})"
  end
end
