# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'

class LineMusicAlbumAlgoliaExporterTest < ActiveSupport::TestCase
  test 'exports the replaced LINE MUSIC album and all tracks as one Algolia record' do
    album = Album.create!(jan_code: "algolia-line-music-#{SecureRandom.hex(4)}", is_touhou: true)
    circle = Circle.create!(name: 'Algolia Export Circle')
    CirclesAlbum.create!(album:, circle:)
    original = Original.create!(
      code: "algolia-line-music-original-#{SecureRandom.hex(4)}",
      title: '原曲タイトル',
      short_title: '原曲',
      original_type: 'windows',
      series_order: 1.0
    )
    original_song = OriginalSong.create!(
      code: "algolia-line-music-song-#{SecureRandom.hex(4)}",
      original:,
      title: '原曲アレンジ',
      track_number: 1
    )
    track = Track.create!(album:, isrc: "JPALG#{SecureRandom.alphanumeric(7).upcase}")
    track.original_songs << original_song
    line_music_album = LineMusicAlbum.create!(
      album:,
      line_music_id: 'algolia-line-album',
      name: 'Algolia LINE MUSIC Album',
      url: 'https://music.line.me/webapp/album/algolia-line-album',
      total_tracks: 1,
      payload: {
        'artists' => [{ 'artist_id' => 'artist-1', 'artist_name' => 'Artist' }],
        'image_url' => 'https://example.test/line-music-image.jpg'
      }
    )
    LineMusicTrack.create!(
      album:,
      track:,
      line_music_album:,
      line_music_id: 'algolia-line-track',
      name: 'Algolia LINE MUSIC Track',
      url: 'https://music.line.me/webapp/track/algolia-line-track',
      disc_number: 1,
      track_number: 1,
      payload: {}
    )

    Dir.mktmpdir('line-music-algolia-export-test') do |directory|
      result = LineMusicAlbumAlgoliaExporter.new(line_music_album:, output_dir: directory).export!

      assert_equal 1, result.record_count
      assert_equal File.join(directory, LineMusicAlbumAlgoliaExporter::FILENAME), result.path.to_s

      rows = JSON.parse(File.read(result.path))

      object_ids = rows.map { |row| row.fetch('objectID') }
      track_names = rows.first.fetch('tracks').map { |row| row.fetch('name') }
      original_song_titles = rows.first.fetch('tracks').first.fetch('original_songs').map { |row| row.fetch('title') }

      assert_equal [album.id], object_ids
      assert_equal 'Algolia LINE MUSIC Album', rows.first.fetch('name')
      assert_equal 'algolia-line-album', rows.first.fetch('url').split('/').last
      assert_equal ['Algolia LINE MUSIC Track'], track_names
      assert_equal ['原曲アレンジ'], original_song_titles
    end
  end

  test 'writes an empty JSON array for a non-Touhou album' do
    album = Album.create!(jan_code: "algolia-line-music-non-touhou-#{SecureRandom.hex(4)}", is_touhou: false)
    line_music_album = LineMusicAlbum.create!(
      album:,
      line_music_id: 'algolia-line-non-touhou-album',
      name: 'Non Touhou LINE MUSIC Album',
      total_tracks: 0,
      payload: {}
    )

    Dir.mktmpdir('line-music-algolia-non-touhou-test') do |directory|
      LineMusicAlbumAlgoliaExporter.new(line_music_album:, output_dir: directory).export!

      assert_equal [], JSON.parse(File.read(File.join(directory, LineMusicAlbumAlgoliaExporter::FILENAME)))
    end
  end

  test 'raises a domain error when the target album has been deleted' do
    album = Album.create!(jan_code: "algolia-line-music-deleted-#{SecureRandom.hex(4)}")
    line_music_album = LineMusicAlbum.create!(
      album:,
      line_music_id: 'algolia-line-deleted-album',
      name: 'Deleted LINE MUSIC Album',
      total_tracks: 0,
      payload: {}
    )
    line_music_album_id = line_music_album.id
    line_music_album.destroy!

    error = assert_raises(LineMusicAlbumAlgoliaExporter::Error) do
      LineMusicAlbumAlgoliaExporter.new(line_music_album:).export!
    end

    assert_match line_music_album_id.to_s, error.message
  end
end
