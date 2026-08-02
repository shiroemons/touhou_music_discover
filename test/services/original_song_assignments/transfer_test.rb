# frozen_string_literal: true

require 'test_helper'

module OriginalSongAssignments
  class TransferTest < ActiveSupport::TestCase
    test 'copies original songs only when one complete catalog has the same ordered track titles' do
      circle = Circle.create!(name: 'Transfer Exact Circle')
      source_album = create_album(jan_code: '4900000000001', circle:)
      target_album = create_album(jan_code: '4900000000002', circle:)
      source_tracks = create_tracks(source_album, %w[JPEXACT00001 JPEXACT00002])
      target_tracks = create_tracks(target_album, %w[JPEXACT10001 JPEXACT10002])
      original_songs = create_original_songs(%w[EXACT-ORIGINAL-01 EXACT-ORIGINAL-02])
      source_tracks.zip(original_songs).each { |track, song| TracksOriginalSong.create!(track:, original_song: song) }

      create_spotify_catalog(source_album, source_tracks, ['First Song', 'Second Song'])
      create_spotify_catalog(target_album, target_tracks, ['First Song (localized)', 'Second Song'])
      create_line_catalog(source_album, source_tracks, ['First Song', 'Second Song'])
      create_line_catalog(target_album, target_tracks, ['First Song', 'Second Song'])

      plan = Transfer.new.plan(album_ids: [target_album.id])

      assert_equal 2, plan.assignments.size
      assert_equal 2, plan.links_to_add
      assert_empty plan.conflicts
      match = plan.matches.sole

      assert_equal :line_music, match.source_service
      assert_equal :line_music, match.target_service
      assert_equal ['First Song', 'Second Song'], match.tracks.map(&:source_track_name)
      assert_equal ['First Song', 'Second Song'], match.tracks.map(&:target_track_name)

      result = Transfer.new.apply!(album_ids: [target_album.id])

      assert_equal 2, result.assigned_tracks
      assert_equal 2, result.created_links
      assert_equal(original_songs.map(&:code), target_tracks.flat_map { |track| track.reload.original_songs.pluck(:code) })

      repeated_result = Transfer.new.apply!(album_ids: [target_album.id])

      assert_equal 0, repeated_result.assigned_tracks
      assert_equal 0, repeated_result.created_links
    end

    test 'rejects albums that share a title but have different complete track lists' do
      circle = Circle.create!(name: 'Transfer Rebirth Circle')
      source_album = create_album(jan_code: '4900000000011', circle:)
      target_album = create_album(jan_code: '4900000000012', circle:)
      source_tracks = create_tracks(source_album, %w[JPREBIRTH001 JPREBIRTH002])
      target_tracks = create_tracks(target_album, %w[JPREBIRTH101])
      original_song = create_original_songs(['REBIRTH-ORIGINAL-01']).sole
      TracksOriginalSong.create!(track: source_tracks.first, original_song:)
      create_spotify_catalog(source_album, source_tracks, ['Rebirth', 'Source Only Song'])
      create_spotify_catalog(target_album, target_tracks, ['Rebirth'])

      plan = Transfer.new.plan(album_ids: [target_album.id])

      assert_empty plan.assignments
      assert_empty plan.matches
      rejection = plan.rejections.sole

      assert_includes rejection.reasons, :track_list_mismatch
      assert_equal 1, rejection.target_track_count
      assert_equal 2, rejection.source_track_count
    end

    test 'accepts alternate track title text only when the ISRC matches at the same position' do
      circle = Circle.create!(name: 'Transfer Localized Circle')
      source_album = create_album(jan_code: '4900000000013', circle:)
      target_album = create_album(jan_code: '4900000000014', circle:)
      source_track = create_tracks(source_album, ['JPLOCALIZED01']).sole
      target_track = create_tracks(target_album, ['JPLOCALIZED01']).sole
      original_song = create_original_songs(['LOCALIZED-ORIGINAL-01']).sole
      TracksOriginalSong.create!(track: source_track, original_song:)
      create_spotify_catalog(source_album, [source_track], ['Milky Way//改二'])
      create_spotify_catalog(target_album, [target_track], ['Milky Way//Second Upgrade'])

      plan = Transfer.new.plan(album_ids: [target_album.id])

      assert_equal [target_track.id], plan.assignments.map(&:target_track_id)
      comparison = plan.matches.sole.tracks.sole

      assert_equal :isrc, comparison.match_basis
      assert_includes 1..99, comparison.title_similarity_percent
    end

    test 'accepts titles that match after applying the same normalization to both sides' do
      circle = Circle.create!(name: 'Transfer Normalized Circle')
      source_album = create_album(jan_code: '4900000000017', circle:)
      target_album = create_album(jan_code: '4900000000018', circle:)
      source_track = create_tracks(source_album, ['JPNORMALIZE01']).sole
      target_track = create_tracks(target_album, ['JPNORMALIZE11']).sole
      original_song = create_original_songs(['NORMALIZED-ORIGINAL-01']).sole
      TracksOriginalSong.create!(track: source_track, original_song:)
      create_spotify_catalog(source_album, [source_track], ['ＦＩＲＳＴ　Song'])
      create_spotify_catalog(target_album, [target_track], ['first song'])

      plan = Transfer.new.plan(album_ids: [target_album.id])

      comparison = plan.matches.sole.tracks.sole

      assert_equal :normalized_title, comparison.match_basis
      assert_equal 100, comparison.title_similarity_percent
    end

    test 'rejects a position when both title and ISRC differ' do
      circle = Circle.create!(name: 'Transfer Identity Circle')
      source_album = create_album(jan_code: '4900000000015', circle:)
      target_album = create_album(jan_code: '4900000000016', circle:)
      source_track = create_tracks(source_album, ['JPIDENTITY001']).sole
      target_track = create_tracks(target_album, ['JPIDENTITY101']).sole
      original_song = create_original_songs(['IDENTITY-ORIGINAL-01']).sole
      TracksOriginalSong.create!(track: source_track, original_song:)
      create_spotify_catalog(source_album, [source_track], ['Source Song'])
      create_spotify_catalog(target_album, [target_track], ['Different Song'])

      plan = Transfer.new.plan(album_ids: [target_album.id])

      assert_empty plan.assignments
      assert_includes plan.rejections.sole.reasons, :track_list_mismatch
    end

    test 'rejects matching track lists when circles differ' do
      source_album = create_album(
        jan_code: '4900000000021',
        circle: Circle.create!(name: 'Transfer Source Circle')
      )
      target_album = create_album(
        jan_code: '4900000000022',
        circle: Circle.create!(name: 'Transfer Target Circle')
      )
      source_track = create_tracks(source_album, ['JPCIRCLE0001']).sole
      target_track = create_tracks(target_album, ['JPCIRCLE1001']).sole
      original_song = create_original_songs(['CIRCLE-ORIGINAL-01']).sole
      TracksOriginalSong.create!(track: source_track, original_song:)
      create_spotify_catalog(source_album, [source_track], ['Same Song'])
      create_spotify_catalog(target_album, [target_track], ['Same Song'])

      plan = Transfer.new.plan(album_ids: [target_album.id])

      assert_empty plan.assignments
      assert_includes plan.rejections.sole.reasons, :circle_mismatch
    end

    test 'requires a complete contiguous catalog before matching' do
      circle = Circle.create!(name: 'Transfer Complete Circle')
      source_album = create_album(jan_code: '4900000000031', circle:)
      target_album = create_album(jan_code: '4900000000032', circle:)
      source_tracks = create_tracks(source_album, %w[JPCOMPLETE001 JPCOMPLETE002])
      target_tracks = create_tracks(target_album, %w[JPCOMPLETE101 JPCOMPLETE102])
      original_song = create_original_songs(['COMPLETE-ORIGINAL-01']).sole
      TracksOriginalSong.create!(track: source_tracks.first, original_song:)
      create_spotify_catalog(source_album, source_tracks, ['First Song', 'Second Song'])
      create_spotify_catalog(target_album, target_tracks, ['First Song', 'Second Song'], positions: [2, 3])

      plan = Transfer.new.plan(album_ids: [target_album.id])

      assert_empty plan.assignments
      assert_empty plan.matches
    end

    private

    def create_album(jan_code:, circle:)
      Album.create!(jan_code:).tap { |album| CirclesAlbum.create!(album:, circle:) }
    end

    def create_tracks(album, isrcs)
      isrcs.map { |isrc| Track.create!(album:, isrc:) }
    end

    def create_original_songs(codes)
      original = Original.create!(
        code: "TRANSFER-#{SecureRandom.hex(4)}",
        title: 'Transfer Test Original',
        short_title: 'Transfer Test',
        original_type: 'other',
        series_order: 999
      )
      codes.each_with_index.map do |code, index|
        OriginalSong.create!(
          code:,
          original:,
          title: "Original Song #{index + 1}",
          composer: 'ZUN',
          track_number: index + 1
        )
      end
    end

    def create_spotify_catalog(album, tracks, titles, positions: nil)
      spotify_album = SpotifyAlbum.create!(
        album:,
        spotify_id: "spotify-transfer-#{SecureRandom.hex(4)}",
        album_type: 'album',
        name: 'Transfer Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        total_tracks: titles.size,
        active: true,
        payload: {}
      )
      tracks.zip(titles).each_with_index do |(track, title), index|
        SpotifyTrack.create!(
          album:,
          track:,
          spotify_album:,
          spotify_id: "spotify-transfer-track-#{SecureRandom.hex(5)}",
          name: title,
          label: Album::TOUHOU_MUSIC_LABEL,
          disc_number: 1,
          track_number: positions&.fetch(index) || (index + 1),
          payload: {}
        )
      end
      spotify_album
    end

    def create_line_catalog(album, tracks, titles)
      line_album = LineMusicAlbum.create!(
        album:,
        line_music_id: "line-transfer-#{SecureRandom.hex(4)}",
        name: 'Transfer Album',
        total_tracks: titles.size,
        payload: {}
      )
      tracks.zip(titles).each_with_index do |(track, title), index|
        LineMusicTrack.create!(
          album:,
          track:,
          line_music_album: line_album,
          line_music_id: "line-transfer-track-#{SecureRandom.hex(5)}",
          name: title,
          disc_number: 1,
          track_number: index + 1,
          payload: {}
        )
      end
    end
  end
end
