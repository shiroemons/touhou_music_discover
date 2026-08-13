# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'

class CatalogSnapshotTest < ActiveSupport::TestCase
  test 'export creates deterministic catalog files and manifest without raw payloads' do
    album = Album.create!(jan_code: "snapshot-album-#{SecureRandom.hex(4)}", is_touhou: true)
    track = Track.create!(album:, isrc: "JPSNAPSHOT#{SecureRandom.alphanumeric(7).upcase}")
    spotify_album = create_spotify_album(album:)
    spotify_track = create_spotify_track(album:, track:, spotify_album:)
    generated_at = Time.zone.local(2026, 8, 13, 12, 0, 0)

    Dir.mktmpdir('catalog-snapshot-test') do |directory|
      result = CatalogSnapshot::Exporter.new(output_dir: directory, now: generated_at).call
      snapshot_path = Pathname.new(result.fetch(:path))
      manifest = JSON.parse(snapshot_path.join('manifest.json').read)

      assert_equal 1, manifest.fetch('schema_version')
      assert_equal result.fetch(:snapshot_id), manifest.fetch('snapshot_id')
      assert_equal generated_at.iso8601, manifest.fetch('generated_at')
      assert_equal CatalogSnapshot::FILES.sort, manifest.fetch('files').map { |file| file.fetch('name') }.sort

      albums = read_jsonl(snapshot_path.join('albums.jsonl'))
      tracks = read_jsonl(snapshot_path.join('tracks.jsonl'))
      service_tracks = read_jsonl(snapshot_path.join('service_tracks.jsonl'))

      album_ids = albums.map { |row| row.fetch('id') }
      track_ids = tracks.map { |row| row.fetch('id') }

      assert_equal [album.id.to_s], album_ids
      assert_equal [track.id.to_s], track_ids
      assert_equal 'available', albums.first.fetch('service_availability').fetch('spotify')
      assert_equal 'available', tracks.first.fetch('service_availability').fetch('spotify')
      assert_equal spotify_track.id.to_s, service_tracks.first.fetch('source_record_id')
      assert_not service_tracks.first.key?('external_id')
      assert_includes snapshot_path.join('albums.jsonl').read, album.display_name
      assert_not_includes snapshot_path.join('albums.jsonl').read, 'payload'
      snapshot_path.glob('*.jsonl').each do |path|
        assert_not_includes path.read, '"video_id"'
        assert_not_includes path.read, '"payload"'
      end

      manifest.fetch('files').each do |file|
        path = snapshot_path.join(file.fetch('name'))

        assert_equal file.fetch('sha256'), Digest::SHA256.file(path).hexdigest
      end
    end
  end

  test 'quality gate blocks a service track whose canonical parent differs from service album' do
    album = Album.create!(jan_code: "snapshot-line-album-#{SecureRandom.hex(4)}", is_touhou: true)
    wrong_album = Album.create!(jan_code: "snapshot-wrong-album-#{SecureRandom.hex(4)}", is_touhou: true)
    wrong_track = Track.create!(album: wrong_album, isrc: "JPWRONG#{SecureRandom.alphanumeric(7).upcase}")
    ytmusic_album = YtmusicAlbum.create!(
      album:,
      browse_id: "MPREb_snapshot_#{SecureRandom.hex(4)}",
      name: 'Snapshot YouTube Album'
    )
    YtmusicTrack.create!(
      album: wrong_album,
      track: wrong_track,
      ytmusic_album:,
      name: 'Wrong parent track',
      video_id: "video-#{SecureRandom.hex(4)}",
      playlist_id: "playlist-#{SecureRandom.hex(4)}",
      url: 'https://music.youtube.com/watch?v=snapshot',
      track_number: 1
    )

    Dir.mktmpdir('catalog-snapshot-failure-test') do |directory|
      error = assert_raises(CatalogSnapshot::Error) do
        CatalogSnapshot::Exporter.new(output_dir: directory).call
      end

      assert_includes error.message, 'Catalog snapshot quality gate failed'
      parent_mismatch = error.report.errors.any? { |issue| issue[:code] == 'service_track_parent_mismatch' }
      remaining_entries = Dir.children(directory).reject { |name| name == 'reports' }

      assert parent_mismatch
      assert_empty remaining_entries
      assert_path_exists Dir[File.join(directory, 'reports', '*.json')].first
    end
  end

  private

  def create_spotify_album(album:)
    SpotifyAlbum.create!(
      album:,
      spotify_id: "spotify-snapshot-#{SecureRandom.hex(4)}",
      album_type: 'album',
      name: 'Snapshot Album',
      label: Album::TOUHOU_MUSIC_LABEL,
      release_date: Date.new(2026, 8, 1),
      total_tracks: 1,
      active: true,
      payload: { 'images' => [], 'available_markets' => ['JP'] }
    )
  end

  def create_spotify_track(album:, track:, spotify_album:)
    SpotifyTrack.create!(
      album:,
      track:,
      spotify_album:,
      spotify_id: "spotify-track-snapshot-#{SecureRandom.hex(4)}",
      name: 'Snapshot Track',
      label: Album::TOUHOU_MUSIC_LABEL,
      disc_number: 1,
      track_number: 1,
      duration_ms: 180_000,
      url: 'https://open.spotify.com/track/snapshot',
      payload: {}
    )
  end

  def read_jsonl(path)
    path.each_line.filter_map { |line| JSON.parse(line) unless line.strip.empty? }
  end
end
