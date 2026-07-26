# frozen_string_literal: true

require 'test_helper'

module Repair
  class YtmusicAlbumPayloadsTest < ActiveSupport::TestCase
    FakeAlbum = Struct.new(:title, :year, :playlist_url, :track_total_count, :tracks_payload, :degraded,
                           keyword_init: true) do
      def as_json(*)
        {
          'title' => title, 'year' => year, 'playlist_url' => playlist_url,
          'track_total_count' => track_total_count, 'tracks' => tracks_payload
        }
      end

      def degraded?
        degraded
      end

      def playable_track_count
        Array(tracks_payload).count { |t| t['video_id'].present? && t['track_number'].to_i.positive? }
      end
    end

    DEFAULT_FIXED_ALBUM_ATTRS = {
      title: 'Fixed Title', year: '2024', playlist_url: 'https://music.youtube.com/playlist?list=PL1',
      track_total_count: 1,
      tracks_payload: [{ 'track_number' => 1, 'video_id' => 'v1', 'playlist_id' => 'pl1', 'title' => 'Track 1' }],
      degraded: false
    }.freeze

    test '対象抽出: 全トラックnull・一部null・tracks欠損の劣化アルバムのみ選ばれ正常アルバムは選ばれない' do
      create_ytmusic_album(payload: payload_with_tracks([complete_track(track_number: 1)]))
      create_ytmusic_album(payload: payload_with_tracks([degraded_track(track_number: 1), degraded_track(track_number: 2)]))
      create_ytmusic_album(payload: payload_with_tracks([complete_track(track_number: 1), degraded_track(track_number: 2)]))
      create_ytmusic_album(payload: {})

      result = run_repair(apply: false)

      assert_equal 3, result[:target_count]
    end

    test '対象抽出: video_idは揃っているがtrack_numberが0のトラックを含むアルバムも対象になる' do
      create_ytmusic_album(payload: payload_with_tracks([complete_track(track_number: 1), track_with_zero_track_number]))

      result = run_repair(apply: false)

      assert_equal 1, result[:target_count]
    end

    test '対象抽出: track_numberがnullのトラックを含むアルバムも対象になる' do
      create_ytmusic_album(payload: payload_with_tracks([complete_track(track_number: 1), track_with_null_track_number]))

      result = run_repair(apply: false)

      assert_equal 1, result[:target_count]
    end

    test '対象抽出: video_idもtrack_numberも揃っている正常アルバムは対象にならない' do
      create_ytmusic_album(payload: payload_with_tracks([complete_track(track_number: 1), complete_track(track_number: 2)]))

      result = run_repair(apply: false)

      assert_equal 0, result[:target_count]
    end

    test 'dry-runの内訳にtrack_number欠落の件数が表示される' do
      create_ytmusic_album(payload: payload_with_tracks([complete_track(track_number: 1), track_with_zero_track_number]))
      out = StringIO.new

      Repair::YtmusicAlbumPayloads.new(apply: false, out:).run

      assert_match(/track_number欠落: 1 件/, out.string)
    end

    test 'dry-runではpayloadを一切変更せずYtMusic::Album.findも呼ばない' do
      untouched = create_ytmusic_album(payload: payload_with_tracks([degraded_track(track_number: 1)]))
      original_payload = untouched.payload

      result = nil
      stub_const(YtMusic, :Album, raising_ytmusic_client) do
        result = run_repair(apply: false)
      end

      assert_not result[:applied]
      assert_equal 1, result[:target_count]
      assert_equal 0, result[:repaired]
      assert_equal original_payload, untouched.reload.payload
    end

    test 'apply正常系: 正常なalbumが返れば修復されpayloadが更新される' do
      ytmusic_album = create_ytmusic_album(payload: payload_with_tracks([degraded_track(track_number: 1)]))
      fixed_album = build_fixed_album

      result = nil
      stub_const(YtMusic, :Album, stub_find_client { |_browse_id| fixed_album }) do
        result = run_repair(apply: true, base_interval: 0)
      end

      assert result[:applied]
      assert_equal 1, result[:repaired]
      assert_equal 0, result[:still_degraded]
      ytmusic_album.reload

      assert_equal 'Fixed Title', ytmusic_album.name
      assert_equal fixed_album.as_json, ytmusic_album.payload
    end

    test 'apply縮退系: max_attempts回試行しても縮退のままならpayloadを変更せずstill_degradedになる' do
      original_payload = payload_with_tracks([degraded_track(track_number: 1)])
      ytmusic_album = create_ytmusic_album(payload: original_payload)
      always_degraded_album = build_fixed_album(degraded: true)
      call_count = 0

      result = nil
      fake_client = stub_find_client do |_browse_id|
        call_count += 1
        always_degraded_album
      end
      stub_const(YtMusic, :Album, fake_client) do
        result = run_repair(apply: true, max_attempts: 3, base_interval: 0)
      end

      assert_equal 3, call_count
      assert_equal 1, result[:still_degraded]
      assert_equal 0, result[:repaired]
      assert_equal original_payload, ytmusic_album.reload.payload
    end

    test '回帰ガードで拒否された場合もstill_degradedに計上されpayloadは変更されない' do
      original_payload = payload_with_two_playable_and_one_null_track
      ytmusic_album = create_ytmusic_album(payload: original_payload)
      regressed_album = build_regressed_album

      result = nil
      stub_const(YtMusic, :Album, stub_find_client { |_browse_id| regressed_album }) do
        result = run_repair(apply: true, base_interval: 0)
      end

      assert_equal 1, result[:still_degraded]
      assert_equal 0, result[:repaired]
      assert_equal original_payload, ytmusic_album.reload.payload
    end

    test 'スキップしたbrowse_idがサマリの結果に含まれる' do
      ytmusic_album = create_ytmusic_album(payload: payload_with_two_playable_and_one_null_track)
      regressed_album = build_regressed_album

      result = nil
      stub_const(YtMusic, :Album, stub_find_client { |_browse_id| regressed_album }) do
        result = run_repair(apply: true, base_interval: 0)
      end

      assert_includes result[:skipped_browse_ids], ytmusic_album.browse_id
    end

    test 'YtMusic::Album.findがnilを返す場合はnot_foundに計上される' do
      create_ytmusic_album(payload: payload_with_tracks([degraded_track(track_number: 1)]))

      result = nil
      stub_const(YtMusic, :Album, stub_find_client { |_browse_id| nil }) do
        result = run_repair(apply: true, base_interval: 0)
      end

      assert_equal 1, result[:not_found]
      assert_equal 0, result[:repaired]
    end

    test '例外が発生しても他のレコードの処理は継続しerrorに計上される' do
      failing = create_ytmusic_album(payload: payload_with_tracks([degraded_track(track_number: 1)]))
      succeeding = create_ytmusic_album(payload: payload_with_tracks([degraded_track(track_number: 1)]))
      fixed_album = build_fixed_album

      result = nil
      fake_client = stub_find_client do |browse_id|
        raise 'boom' if browse_id == failing.browse_id

        fixed_album
      end
      stub_const(YtMusic, :Album, fake_client) do
        result = run_repair(apply: true, base_interval: 0)
      end

      assert_equal 1, result[:error]
      assert_equal 1, result[:repaired]
      assert_equal 'Fixed Title', succeeding.reload.name
    end

    test '冪等性: 修復後に再実行すると対象0件になる' do
      create_ytmusic_album(payload: payload_with_tracks([degraded_track(track_number: 1)]))
      fixed_album = build_fixed_album

      stub_const(YtMusic, :Album, stub_find_client { |_browse_id| fixed_album }) do
        first_result = run_repair(apply: true, base_interval: 0)
        second_result = run_repair(apply: false)

        assert_equal 1, first_result[:repaired]
        assert_equal 0, second_result[:target_count]
      end
    end

    test 'sync_tracks: 修復後にtrack_numberで突き合わせてYtmusicTrackが同期される' do
      album = create_album
      track1 = create_track(album)
      track2 = create_track(album)
      track_zero = create_track(album)
      ytmusic_album = create_ytmusic_album(
        album:,
        payload: payload_with_tracks([degraded_track(track_number: 1), degraded_track(track_number: 2)])
      )
      ytmusic_track1 = create_ytmusic_track(ytmusic_album:, album:, track: track1, track_number: 1, name: 'Old 1')
      ytmusic_track2 = create_ytmusic_track(ytmusic_album:, album:, track: track2, track_number: 2, name: 'Old 2')
      ytmusic_track_zero = create_ytmusic_track(ytmusic_album:, album:, track: track_zero, track_number: 0, name: 'Old 0')
      fixed_album = build_fixed_album(tracks_payload: [
                                        { 'track_number' => 1, 'video_id' => 'new1', 'playlist_id' => 'newpl1', 'title' => 'New Title 1' },
                                        { 'track_number' => 2, 'video_id' => 'new2', 'playlist_id' => 'newpl2', 'title' => 'New Title 2' }
                                      ])

      stub_const(YtMusic, :Album, stub_find_client { |_browse_id| fixed_album }) do
        run_repair(apply: true, base_interval: 0, sync_tracks: true)
      end

      assert_equal 'New Title 1', ytmusic_track1.reload.name
      assert_equal 'new1', ytmusic_track1.payload['video_id']
      assert_equal 'New Title 2', ytmusic_track2.reload.name
      assert_equal 'new2', ytmusic_track2.payload['video_id']
      assert_equal 'Old 0', ytmusic_track_zero.reload.name
    end

    private

    # limit / workers / max_attempts / base_interval / sync_tracks はRepair::YtmusicAlbumPayloadsの
    # デフォルト値をそのまま使う。個別のテストで変えたい値だけを渡す。
    def run_repair(apply:, **)
      Repair::YtmusicAlbumPayloads.new(apply:, out: StringIO.new, **).run
    end

    # `YtMusic::Album.find` が一度でも呼ばれたら失敗させ、dry-run時にAPI呼び出しがないことを検証するためのfake。
    def raising_ytmusic_client
      stub_find_client { |_browse_id| raise 'YtMusic::Album.find should not be called during dry-run' }
    end

    def stub_find_client(&)
      Class.new do
        define_singleton_method(:find, &)
      end
    end

    def build_fixed_album(**overrides)
      FakeAlbum.new(**DEFAULT_FIXED_ALBUM_ATTRS, **overrides)
    end

    def payload_with_tracks(tracks)
      { 'tracks' => tracks }
    end

    # 回帰ガードのテスト用: playable 2件 + null 1件（対象抽出SQLの「一部null」条件にも合致する）。
    def payload_with_two_playable_and_one_null_track
      tracks = [
        complete_track(track_number: 1),
        complete_track(track_number: 2),
        degraded_track(track_number: 3)
      ]
      payload_with_tracks(tracks)
    end

    # 回帰ガードのテスト用: 既存のplayable 2件より少ないplayable 1件だけを返すfetch結果。
    def build_regressed_album
      build_fixed_album(
        tracks_payload: [{ 'track_number' => 1, 'video_id' => 'v1', 'playlist_id' => 'pl1', 'title' => 'T' }]
      )
    end

    def complete_track(track_number:, video_id: "vid-#{SecureRandom.hex(4)}")
      {
        'track_number' => track_number, 'video_id' => video_id, 'playlist_id' => 'PL123', 'title' => 'Track',
        'url' => "https://music.youtube.com/watch?v=#{video_id}&list=PL123"
      }
    end

    def degraded_track(track_number:)
      { 'track_number' => track_number, 'video_id' => nil, 'playlist_id' => nil, 'title' => 'Track' }
    end

    def track_with_zero_track_number(track_number: 0, video_id: "vid-#{SecureRandom.hex(4)}")
      { 'track_number' => track_number, 'video_id' => video_id, 'playlist_id' => 'PL123', 'title' => 'Track' }
    end

    def track_with_null_track_number(video_id: "vid-#{SecureRandom.hex(4)}")
      { 'track_number' => nil, 'video_id' => video_id, 'playlist_id' => 'PL123', 'title' => 'Track' }
    end

    def create_album
      Album.create!(jan_code: "repair-#{SecureRandom.hex(6)}")
    end

    def create_track(album)
      Track.create!(album:, isrc: "JPRP#{SecureRandom.alphanumeric(8).upcase}")
    end

    def create_ytmusic_album(payload:, album: create_album, browse_id: "repair-browse-#{SecureRandom.hex(4)}")
      YtmusicAlbum.create!(album:, browse_id:, name: 'Repair Target Album', payload:)
    end

    def create_ytmusic_track(ytmusic_album:, album:, track:, track_number:, name:)
      YtmusicTrack.create!(
        album:, ytmusic_album:, track:, track_number:, name:,
        video_id: "old-#{SecureRandom.hex(4)}", playlist_id: "oldpl-#{SecureRandom.hex(4)}",
        payload: { 'video_id' => 'old' }
      )
    end
  end
end
