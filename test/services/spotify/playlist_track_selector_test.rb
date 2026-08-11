# frozen_string_literal: true

require 'test_helper'

module Spotify
  class PlaylistTrackSelectorTest < ActiveSupport::TestCase
    AlbumStub = Struct.new(:active) do
      def active?
        active
      end
    end
    TrackStub = Struct.new(:track_id, :spotify_id, :spotify_album, :isrc)

    def spotify_track(track_id:, spotify_id:, active:, isrc:)
      TrackStub.new(track_id, spotify_id, AlbumStub.new(active), isrc)
    end

    test 'keeps the only active Spotify ID for a duplicated internal track' do
      selection = PlaylistTrackSelector.select([
                                                 spotify_track(track_id: 'TRACK1', spotify_id: 'OLD', active: false, isrc: 'ISRC1'),
                                                 spotify_track(track_id: 'TRACK1', spotify_id: 'NEW', active: true, isrc: 'ISRC1')
                                               ])

      assert_equal ['NEW'], selection.tracks.map(&:spotify_id)
      assert_equal 2, selection.raw_count
      assert_equal 1, selection.canonical_count
      assert_equal 1, selection.duplicate_count
      assert_not selection.ambiguous?
    end

    test 'uses ISRC to detect the same recording across different internal Track records' do
      selection = PlaylistTrackSelector.select([
                                                 spotify_track(track_id: 'TRACK1', spotify_id: 'A', active: false, isrc: 'ISRC1'),
                                                 spotify_track(track_id: 'TRACK2', spotify_id: 'B', active: true, isrc: 'ISRC1')
                                               ])

      assert_equal ['B'], selection.tracks.map(&:spotify_id)
      assert_equal 1, selection.duplicate_count
      assert_not selection.ambiguous?
    end

    test 'does not guess when more than one active candidate remains' do
      selection = PlaylistTrackSelector.select([
                                                 spotify_track(track_id: 'TRACK1', spotify_id: 'A', active: true, isrc: 'ISRC1'),
                                                 spotify_track(track_id: 'TRACK1', spotify_id: 'B', active: true, isrc: 'ISRC1')
                                               ])

      assert_empty selection.tracks
      assert_predicate selection, :ambiguous?
      assert_equal 1, selection.ambiguous_groups.size
      assert_equal %w[A B], selection.ambiguous_groups.first['spotify_ids']
    end

    test 'keeps a single inactive candidate when there is no competing candidate' do
      selection = PlaylistTrackSelector.select([
                                                 spotify_track(track_id: 'TRACK1', spotify_id: 'ONLY', active: false, isrc: 'ISRC1')
                                               ])

      assert_equal ['ONLY'], selection.tracks.map(&:spotify_id)
      assert_not selection.ambiguous?
    end
  end
end
