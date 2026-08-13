# frozen_string_literal: true

require 'test_helper'

class LineMusicTrackParentRepairTest < ActiveSupport::TestCase
  test 'repairs canonical album and track ids from the target album provider catalog' do
    old_album = Album.create!(jan_code: "line-music-repair-old-#{SecureRandom.hex(4)}")
    target_album = Album.create!(jan_code: "line-music-repair-target-#{SecureRandom.hex(4)}")
    old_tracks = Array.new(2) do
      Track.create!(album: old_album, isrc: "OLD-ISRC-#{SecureRandom.hex(4)}")
    end
    target_tracks = Array.new(2) do
      Track.create!(album: target_album, isrc: "TARGET-ISRC-#{SecureRandom.hex(4)}")
    end
    apple_music_album = AppleMusicAlbum.create!(
      album: target_album,
      apple_music_id: "apple-album-#{SecureRandom.hex(4)}",
      name: 'Target Album',
      label: Album::TOUHOU_MUSIC_LABEL,
      total_tracks: 2,
      payload: {}
    )
    target_tracks.each_with_index do |track, index|
      AppleMusicTrack.create!(
        album: target_album,
        track:,
        apple_music_album:,
        apple_music_id: "apple-track-#{SecureRandom.hex(4)}",
        name: "Track #{index + 1}",
        label: Album::TOUHOU_MUSIC_LABEL,
        url: '',
        disc_number: 1,
        track_number: index + 1,
        payload: {}
      )
    end
    line_music_album = LineMusicAlbum.create!(
      album: target_album,
      line_music_id: "lm-album-#{SecureRandom.hex(4)}",
      name: 'Target Album',
      total_tracks: 2,
      payload: {}
    )
    line_tracks = old_tracks.each_with_index.map do |track, index|
      LineMusicTrack.create!(
        album: old_album,
        track:,
        line_music_album:,
        line_music_id: "lm-track-#{SecureRandom.hex(4)}",
        name: "Track #{index + 1}",
        url: '',
        disc_number: 1,
        track_number: index + 1,
        payload: {}
      )
    end

    dry_run = LineMusicTrackParentRepair.new.call

    plan = dry_run.plans.find { |candidate| candidate.line_music_album.id == line_music_album.id }

    assert plan

    assert_predicate plan, :ready?
    assert_equal 2, plan.repairs.size
    assert_equal 0, dry_run.updated_count
    assert_equal old_album.id, line_tracks.first.reload.album_id
    assert_equal old_tracks.first.id, line_tracks.first.track_id

    result = LineMusicTrackParentRepair.new(apply: true).call

    assert_equal 2, result.updated_count
    assert_equal [target_album.id], line_tracks.map { |line_track| line_track.reload.album_id }.uniq
    repaired_track_ids = line_tracks.map { |line_track| line_track.reload.track_id }

    assert_equal target_tracks.map(&:id), repaired_track_ids
  end
end
