# frozen_string_literal: true

require 'test_helper'

class LineMusicAlbumReplacementTest < ActiveSupport::TestCase
  ApiArtist = Struct.new(:artist_name, keyword_init: true)
  ApiAlbum = Struct.new(:album_id, :album_title, :release_date, :track_total_count, :artists, keyword_init: true) do
    def as_json(*)
      {
        'album_id' => album_id,
        'album_title' => album_title,
        'release_date' => release_date,
        'track_total_count' => track_total_count
      }
    end
  end
  ApiTrack = Struct.new(:track_id, :track_title, :disc_number, :track_number, keyword_init: true) do
    def as_json(*)
      {
        'track_id' => track_id,
        'track_title' => track_title,
        'disc_number' => disc_number,
        'track_number' => track_number
      }
    end
  end

  test 'replaces the album and all track IDs atomically while keeping history' do
    album, line_music_album, source_tracks = create_catalog
    stale_track = Track.create!(album:, isrc: "ISRC-STale-#{SecureRandom.hex(4)}")
    stale_line_track = LineMusicTrack.create!(
      album:,
      track: stale_track,
      line_music_album:,
      line_music_id: 'old-stale',
      name: '旧カタログ曲',
      url: 'https://music.line.me/webapp/track/old-stale',
      disc_number: 1,
      track_number: 4,
      payload: {}
    )
    existing_rows = source_tracks.first(2).map.with_index do |source_track, index|
      LineMusicTrack.create!(
        album:,
        track: source_track,
        line_music_album:,
        line_music_id: "old-#{index + 1}",
        name: "Track #{index + 1}",
        url: "https://music.line.me/webapp/track/old-#{index + 1}",
        disc_number: 1,
        track_number: index + 1,
        payload: {}
      )
    end
    replacement_candidate = LineMusicAlbumReplacementCandidate.create!(
      line_music_album:,
      line_music_id: 'new-album-id',
      name: 'Replacement Album',
      url: 'https://music.line.me/webapp/album/new-album-id',
      total_tracks: 3,
      payload: {}
    )
    new_album = build_api_album('new-album-id', total_tracks: 3)
    new_tracks = build_api_tracks

    with_line_music_api(album: new_album, tracks: new_tracks) do
      plan = LineMusicAlbumReplacement.new(
        line_music_album:,
        new_line_music_id: 'new-album-id',
        expected_old_line_music_id: 'old-album-id'
      ).prepare

      assert_predicate plan, :ready?
      assert_equal({ 'created' => 1, 'updated' => 2, 'removed' => 1, 'unchanged' => 0 }, plan.diff)

      result = LineMusicAlbumReplacement.new(
        line_music_album:,
        new_line_music_id: 'new-album-id',
        expected_old_line_music_id: 'old-album-id'
      ).apply!(action_run_id: 'run-replacement-test')

      assert_equal 'old-album-id', result.old_line_music_id
      assert_equal 'new-album-id', result.new_line_music_id
      assert_equal 1, result.created_count
      assert_equal 2, result.updated_count
      assert_equal 1, result.removed_count
    end

    line_music_album.reload

    assert_equal 'new-album-id', line_music_album.line_music_id
    assert_equal 'https://music.line.me/webapp/album/new-album-id', line_music_album.url
    assert_equal 3, line_music_album.total_tracks
    assert_not LineMusicTrack.unscoped.exists?(id: stale_line_track.id)

    saved_rows = LineMusicTrack.unscoped.where(line_music_album_id: line_music_album.id)

    existing_rows.each { |row| assert saved_rows.exists?(id: row.id), "expected existing row #{row.id} to be reused" }
    assert_equal %w[new-track-1 new-track-2 new-track-3], saved_rows.order(:track_number).pluck(:line_music_id)

    history = LineMusicAlbumReplacementHistory.find_by!(action_run_id: 'run-replacement-test')

    assert_equal 'old-album-id', history.old_line_music_id
    assert_equal 'new-album-id', history.new_line_music_id
    assert_equal 3, history.before_snapshot.fetch('tracks').size
    assert_equal 3, history.after_snapshot.fetch('tracks').size
    assert_equal 'applied', replacement_candidate.reload.status
  end

  test 'does not write anything when one track cannot be matched' do
    _album, line_music_album, _source_tracks = create_catalog
    old_track = Track.find_by!(jan_code: line_music_album.album.jan_code, isrc: 'ISRC-1')
    LineMusicTrack.create!(
      album: line_music_album.album,
      track: old_track,
      line_music_album:,
      line_music_id: 'old-1',
      name: 'Track 1',
      url: 'https://music.line.me/webapp/track/old-1',
      disc_number: 1,
      track_number: 1,
      payload: {}
    )
    before_id = line_music_album.line_music_id
    before_track_ids = LineMusicTrack.unscoped.where(line_music_album_id: line_music_album.id).pluck(:line_music_id)

    with_line_music_api(album: build_api_album('new-mismatch-id', total_tracks: 3), tracks: build_api_tracks.first(2)) do
      plan = LineMusicAlbumReplacement.new(
        line_music_album:,
        new_line_music_id: 'new-mismatch-id',
        expected_old_line_music_id: before_id
      ).prepare

      assert_not_predicate plan, :ready?
      assert_includes plan.errors.join, '曲数が一致しません'
      assert_raises(LineMusicAlbumReplacement::Error) do
        LineMusicAlbumReplacement.new(
          line_music_album:,
          new_line_music_id: 'new-mismatch-id',
          expected_old_line_music_id: before_id
        ).apply!
      end
    end

    assert_equal before_id, line_music_album.reload.line_music_id
    assert_equal before_track_ids, LineMusicTrack.unscoped.where(line_music_album_id: line_music_album.id).pluck(:line_music_id)
    assert_empty LineMusicAlbumReplacementHistory.where(line_music_album_id: line_music_album.id)
  end

  test 'rejects a custom URL that does not contain the new album ID' do
    _album, line_music_album, _source_tracks = create_catalog

    with_line_music_api(album: build_api_album('new-url-id', total_tracks: 3), tracks: build_api_tracks) do
      plan = LineMusicAlbumReplacement.new(
        line_music_album:,
        new_line_music_id: 'new-url-id',
        new_url: 'https://music.line.me/webapp/album/another-id'
      ).prepare

      assert_not_predicate plan, :ready?
      assert_includes plan.errors.join, '新しいアルバムID'
    end
  end

  test 'rolls back the album and all track changes when history cannot be written' do
    album, line_music_album, source_tracks = create_catalog
    source_tracks.each_with_index do |source_track, index|
      LineMusicTrack.create!(
        album:,
        track: source_track,
        line_music_album:,
        line_music_id: "old-track-#{index + 1}",
        name: "Old Track #{index + 1}",
        url: "https://music.line.me/webapp/track/old-track-#{index + 1}",
        disc_number: 1,
        track_number: index + 1,
        payload: {}
      )
    end
    old_line_music_id = line_music_album.line_music_id
    old_track_ids = LineMusicTrack.unscoped.where(line_music_album_id: line_music_album.id).order(:track_number).pluck(:line_music_id)

    with_line_music_api(album: build_api_album('transaction-new-id', total_tracks: 3), tracks: build_api_tracks) do
      with_singleton_method(
        LineMusicAlbumReplacementHistory,
        :create!,
        ->(**_attributes) { raise LineMusicAlbumReplacement::Error, '履歴保存に失敗しました。' }
      ) do
        assert_raises(LineMusicAlbumReplacement::Error) do
          LineMusicAlbumReplacement.new(
            line_music_album:,
            new_line_music_id: 'transaction-new-id',
            expected_old_line_music_id: old_line_music_id
          ).apply!
        end
      end
    end

    assert_equal old_line_music_id, line_music_album.reload.line_music_id
    assert_equal old_track_ids, LineMusicTrack.unscoped.where(line_music_album_id: line_music_album.id).order(:track_number).pluck(:line_music_id)
    assert_empty LineMusicAlbumReplacementHistory.where(line_music_album_id: line_music_album.id)
  end

  test 'detects and stores an alternate ID without creating a duplicate album row' do
    album, line_music_album, _source_tracks = create_catalog
    candidate = build_api_album('detected-new-id', total_tracks: 3)

    with_line_music_search([candidate]) do
      plan = LineMusicAlbumReplacementDetector.new(line_music_album:).prepare

      assert_predicate plan, :ready?
      assert_equal ['detected-new-id'], plan.candidates.map(&:album_id)

      result = LineMusicAlbumReplacementDetector.new(line_music_album:).detect!

      assert_equal ['detected-new-id'], result.candidate_ids
    end

    assert_equal 1, LineMusicAlbumReplacementCandidate.where(line_music_album_id: line_music_album.id).count
    assert_equal 'detected-new-id', line_music_album.pending_replacement_line_music_id

    assert_no_difference -> { LineMusicAlbum.unscoped.count } do
      LineMusicAlbum.save_album(album.id, candidate)
    end
    assert_equal 1, LineMusicAlbumReplacementCandidate.where(line_music_album_id: line_music_album.id).count
  end

  private

  def create_catalog
    album = Album.create!(jan_code: "line-music-replacement-#{SecureRandom.hex(4)}")
    release_date = Date.new(2026, 5, 4)
    source_tracks = Array.new(3) do |index|
      Track.create!(album:, isrc: "ISRC-#{index + 1}")
    end
    spotify_album = SpotifyAlbum.create!(
      album:,
      spotify_id: "spotify-album-#{SecureRandom.hex(4)}",
      album_type: 'album',
      name: 'Replacement Album',
      label: Album::TOUHOU_MUSIC_LABEL,
      release_date:,
      total_tracks: 3,
      active: true,
      payload: { 'artists' => [{ 'name' => 'Artist' }] }
    )
    source_tracks.each_with_index do |track, index|
      SpotifyTrack.create!(
        album:,
        track:,
        spotify_album:,
        spotify_id: "spotify-track-#{index + 1}-#{SecureRandom.hex(3)}",
        name: "Track #{index + 1}",
        label: Album::TOUHOU_MUSIC_LABEL,
        disc_number: 1,
        track_number: index + 1,
        payload: {}
      )
    end
    line_music_album = LineMusicAlbum.create!(
      album:,
      line_music_id: 'old-album-id',
      name: 'Replacement Album',
      url: 'https://music.line.me/webapp/album/old-album-id',
      release_date:,
      total_tracks: 3,
      payload: {}
    )
    [album.reload, line_music_album.reload, source_tracks]
  end

  def build_api_album(id, total_tracks:)
    ApiAlbum.new(
      album_id: id,
      album_title: 'Replacement Album',
      release_date: Date.new(2026, 5, 4),
      track_total_count: total_tracks,
      artists: [ApiArtist.new(artist_name: 'Artist')]
    )
  end

  def build_api_tracks
    Array.new(3) do |index|
      ApiTrack.new(
        track_id: "new-track-#{index + 1}",
        track_title: "Track #{index + 1}",
        disc_number: 1,
        track_number: index + 1
      )
    end
  end

  def with_line_music_api(album:, tracks:, &)
    with_singleton_method(LineMusic::Album, :find, ->(_id) { album }) do
      with_singleton_method(LineMusic::Album, :tracks, ->(_id, **) { tracks }, &)
    end
  end

  def with_line_music_search(albums, &)
    with_singleton_method(LineMusic::Album, :search, ->(_query, **) { albums }, &)
  end

  def with_singleton_method(target, method_name, replacement, &)
    singleton_class = target.singleton_class
    original_method = target.method(method_name)
    singleton_class.define_method(method_name, &replacement)
    yield
  ensure
    singleton_class.define_method(method_name, original_method)
  end
end
