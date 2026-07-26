# frozen_string_literal: true

require 'test_helper'

module DistributionDate
  class YtmusicCollectorTest < ActiveSupport::TestCase
    # YtMusic::Video相当のFake。本リポジトリはwebmock/vcrを使わないため、
    # HTTPを伴う実クラスの代わりにこのFakeでコレクタの保存・集計処理だけを検証する。
    FakeVideo = Struct.new(:publish_date, :upload_date, :release_date, :provided_by, keyword_init: true) do
      def art_track?
        provided_by.present?
      end

      def metadata
        { 'provided_by' => provided_by, 'publish_date' => publish_date&.iso8601 }
      end
    end

    test 'dry-run: DBを更新せず対象件数が正しく算出されYtMusic::Video.findも呼ばれない' do
      album = create_album
      ytmusic_album = create_ytmusic_album(album:)
      create_track_row(ytmusic_album:, album:)

      result = nil
      stub_const(YtMusic, :Video, raising_ytmusic_video_client) do
        result = run_collector(apply: false)
      end

      assert_not result[:applied]
      assert_equal 1, result[:target_count]
      assert_nil ytmusic_album.reload.distributed_on
      assert_nil ytmusic_album.reload.distribution_fetched_at
    end

    test 'apply正常系: トラックのvideo_fetched_atが埋まりアルバムのdistributed_onが算出される' do
      album = create_album
      ytmusic_album = create_ytmusic_album(album:)
      track = create_track_row(ytmusic_album:, album:)
      video = FakeVideo.new(publish_date: Date.new(2026, 6, 29), upload_date: Date.new(2026, 6, 28),
                            release_date: nil, provided_by: nil)

      result = nil
      stub_const(YtMusic, :Video, stub_find_client { |_video_id| video }) do
        result = run_collector(apply: true, base_interval: 0)
      end

      assert result[:applied]
      assert_equal 1, result[:updated]
      assert_equal 1, result[:fetched_videos]
      assert_not_nil track.reload.video_fetched_at
      assert_equal Date.new(2026, 6, 29), track.published_on
      assert_equal Date.new(2026, 6, 30), ytmusic_album.reload.distributed_on
    end

    test 'only_missing: trueのとき既にdistribution_track_metadataにfetched_atが記録済みのvideo_idは再取得されない' do
      album = create_album
      ytmusic_album = create_ytmusic_album(album:)
      fetched_track = create_track_row(ytmusic_album:, album:)
      create_track_row(ytmusic_album:, album:)
      ytmusic_album.update!(distribution_track_metadata: [distribution_metadata_entry(video_id: fetched_track.video_id)])
      video = FakeVideo.new(publish_date: Date.new(2026, 6, 29), upload_date: nil, release_date: nil, provided_by: nil)
      call_count = 0

      stub_const(YtMusic, :Video, stub_find_client do |_video_id|
        call_count += 1
        video
      end) do
        run_collector(apply: true, base_interval: 0)
      end

      assert_equal 1, call_count
    end

    test 'only_missing: trueはtrack行が無いアルバムでもdistribution_track_metadataのfetched_atを見て差分取得する' do
      album = create_album
      ytmusic_album = create_ytmusic_album(album:)
      ytmusic_album.update!(
        payload: { 'tracks' => [
          payload_track(video_id: 'vid-already-fetched', track_number: 1),
          payload_track(video_id: 'vid-not-fetched', track_number: 2)
        ] },
        distribution_track_metadata: [distribution_metadata_entry(video_id: 'vid-already-fetched')]
      )
      call_count = 0

      stub_const(YtMusic, :Video, stub_find_client do |video_id|
        call_count += 1

        assert_equal 'vid-not-fetched', video_id
        FakeVideo.new(publish_date: Date.new(2026, 6, 29), upload_date: nil, release_date: nil, provided_by: nil)
      end) do
        run_collector(apply: true, base_interval: 0)
      end

      assert_equal 1, call_count
    end

    test 'only_missing: falseのとき既に取得済みのトラックも含め全トラックが再取得される' do
      album = create_album
      ytmusic_album = create_ytmusic_album(album:)
      create_track_row(ytmusic_album:, album:, video_fetched_at: Time.current)
      create_track_row(ytmusic_album:, album:)
      video = FakeVideo.new(publish_date: Date.new(2026, 6, 29), upload_date: nil, release_date: nil, provided_by: nil)
      call_count = 0

      stub_const(YtMusic, :Video, stub_find_client do |_video_id|
        call_count += 1
        video
      end) do
        run_collector(apply: true, base_interval: 0, only_missing: false)
      end

      assert_equal 2, call_count
    end

    test 'all: false（既定）のとき配信日が確定済みのアルバムは対象外になる' do
      resolved_album = create_album
      resolved_ytmusic_album = create_ytmusic_album(album: resolved_album)
      create_resolved_track(ytmusic_album: resolved_ytmusic_album, album: resolved_album)
      resolved_ytmusic_album.recalculate_distribution!

      pending_album = create_album
      pending_ytmusic_album = create_ytmusic_album(album: pending_album)
      create_track_row(ytmusic_album: pending_ytmusic_album, album: pending_album)

      result = run_collector(apply: false)

      assert_equal 1, result[:target_count]
    end

    test 'all: trueのとき配信日が確定済みのアルバムも対象になる' do
      resolved_album = create_album
      resolved_ytmusic_album = create_ytmusic_album(album: resolved_album)
      create_resolved_track(ytmusic_album: resolved_ytmusic_album, album: resolved_album)
      resolved_ytmusic_album.recalculate_distribution!

      pending_album = create_album
      pending_ytmusic_album = create_ytmusic_album(album: pending_album)
      create_track_row(ytmusic_album: pending_ytmusic_album, album: pending_album)

      result = run_collector(apply: false, all: true)

      assert_equal 2, result[:target_count]
    end

    test '1アルバムで例外が発生しても他のアルバムの処理は継続しerrorに計上される' do
      failing_album = create_album
      failing_ytmusic_album = create_ytmusic_album(album: failing_album)
      create_track_row(ytmusic_album: failing_ytmusic_album, album: failing_album)

      succeeding_album = create_album
      succeeding_ytmusic_album = create_ytmusic_album(album: succeeding_album)
      succeeding_track = create_track_row(ytmusic_album: succeeding_ytmusic_album, album: succeeding_album)

      video = FakeVideo.new(publish_date: Date.new(2026, 6, 29), upload_date: nil, release_date: nil, provided_by: nil)

      result = nil
      stub_const(YtMusic, :Video, stub_find_client { |_video_id| video }) do
        with_recalculate_distribution_raising_for(failing_ytmusic_album.id) do
          result = run_collector(apply: true, base_interval: 0)
        end
      end

      assert_equal 1, result[:error]
      assert_equal 1, result[:updated]
      assert_not_nil succeeding_track.reload.video_fetched_at
    end

    test '全トラックの取得に失敗したアルバムはfailedとして集計される' do
      album = create_album
      ytmusic_album = create_ytmusic_album(album:)
      create_track_row(ytmusic_album:, album:)

      result = nil
      stub_const(YtMusic, :Video, stub_find_client { |_video_id| nil }) do
        result = run_collector(apply: true, base_interval: 0, max_attempts: 2)
      end

      assert_equal 1, result[:failed]
      assert_equal 0, result[:updated]
      assert_equal 'failed', ytmusic_album.reload.distribution_source
    end

    test 'track行が1件も無いアルバムでもpayloadのvideo_idから配信日が集計できる（track行がアルバム取り込みより遅れて作られる問題の回帰テスト）' do
      album = create_album
      ytmusic_album = create_ytmusic_album(album:)
      ytmusic_album.update!(payload: { 'tracks' => [payload_track(video_id: 'vid-payload-only', track_number: 1)] })
      video = FakeVideo.new(publish_date: Date.new(2026, 6, 29), upload_date: nil, release_date: nil, provided_by: 'Rightsscale')

      result = nil
      stub_const(YtMusic, :Video, stub_find_client { |_video_id| video }) do
        result = run_collector(apply: true, base_interval: 0)
      end

      assert_equal 1, result[:updated]
      assert_equal 1, result[:fetched_videos]
      assert_equal 0, ytmusic_album.ytmusic_tracks.count
      assert_equal Date.new(2026, 6, 30), ytmusic_album.reload.distributed_on
    end

    test 'track行が一部しか無いアルバムでもpayload全件のvideo_idから集計される' do
      album = create_album
      ytmusic_album = create_ytmusic_album(album:)
      ytmusic_album.update!(payload: { 'tracks' => [
                              payload_track(video_id: 'vid-partial-1', track_number: 1),
                              payload_track(video_id: 'vid-partial-2', track_number: 2)
                            ] })
      create_track_row(ytmusic_album:, album:, video_id: 'vid-partial-1')
      call_count = 0

      stub_const(YtMusic, :Video, stub_find_client do |_video_id|
        call_count += 1
        FakeVideo.new(publish_date: Date.new(2026, 6, 29), upload_date: nil, release_date: nil, provided_by: nil)
      end) do
        run_collector(apply: true, base_interval: 0)
      end

      assert_equal 2, call_count
      assert_equal 2, ytmusic_album.reload.distribution_track_metadata.size
      assert_equal 2, ytmusic_album.distribution_stats['total_tracks']
    end

    test '取得結果がdistribution_track_metadataに保存されvideo_id・fetched_at・各日付が入ること' do
      album = create_album
      ytmusic_album = create_ytmusic_album(album:)
      ytmusic_album.update!(payload: { 'tracks' => [payload_track(video_id: 'vid-metadata-store', track_number: 1)] })
      video = FakeVideo.new(publish_date: Date.new(2026, 6, 29), upload_date: Date.new(2026, 6, 28),
                            release_date: Date.new(2026, 5, 4), provided_by: 'Rightsscale')

      stub_const(YtMusic, :Video, stub_find_client { |_video_id| video }) do
        run_collector(apply: true, base_interval: 0)
      end

      entry = ytmusic_album.reload.distribution_track_metadata.first

      assert_equal 'vid-metadata-store', entry['video_id']
      assert_equal 1, entry['track_number']
      assert_equal '2026-06-29', entry['published_on']
      assert_equal '2026-06-28', entry['uploaded_on']
      assert_equal '2026-05-04', entry['original_released_on']
      assert_equal 'Rightsscale', entry['provided_by']
      assert entry['art_track']
      assert_not_nil entry['fetched_at']
    end

    test '取得に失敗した動画もdistribution_track_metadataにfetched_at付きで記録される' do
      album = create_album
      ytmusic_album = create_ytmusic_album(album:)
      ytmusic_album.update!(payload: { 'tracks' => [payload_track(video_id: 'vid-fetch-fail', track_number: 1)] })

      stub_const(YtMusic, :Video, stub_find_client { |_video_id| nil }) do
        run_collector(apply: true, base_interval: 0, max_attempts: 1)
      end

      entry = ytmusic_album.reload.distribution_track_metadata.first

      assert_equal 'vid-fetch-fail', entry['video_id']
      assert_nil entry['published_on']
      assert_not entry['art_track']
      assert_not_nil entry['fetched_at']
    end

    test 'payloadにtracksが無いアルバムはytmusic_tracksの行にフォールバックする' do
      album = create_album
      ytmusic_album = create_ytmusic_album(album:)
      track = create_track_row(ytmusic_album:, album:)
      video = FakeVideo.new(publish_date: Date.new(2026, 6, 29), upload_date: nil, release_date: nil, provided_by: nil)

      stub_const(YtMusic, :Video, stub_find_client { |_video_id| video }) do
        run_collector(apply: true, base_interval: 0)
      end

      assert_not_nil track.reload.video_fetched_at
      assert_equal Date.new(2026, 6, 30), ytmusic_album.reload.distributed_on
    end

    test 'limitが効くこと' do
      3.times do
        album = create_album
        ytmusic_album = create_ytmusic_album(album:)
        create_track_row(ytmusic_album:, album:)
      end

      result = run_collector(apply: false, limit: 2)

      assert_equal 2, result[:target_count]
    end

    test 'apply: trueのときprogress_callbackが開始時にreset: trueで1回、処理毎に1回呼ばれる' do
      album = create_album
      ytmusic_album = create_ytmusic_album(album:)
      create_track_row(ytmusic_album:, album:)
      video = FakeVideo.new(publish_date: Date.new(2026, 6, 29), upload_date: nil, release_date: nil, provided_by: nil)

      calls = []
      progress_callback = ->(**kwargs) { calls << kwargs }

      stub_const(YtMusic, :Video, stub_find_client { |_video_id| video }) do
        DistributionDate::YtmusicCollector.new(apply: true, base_interval: 0, out: StringIO.new, progress_callback:).run
      end

      assert_equal 2, calls.size
      assert_equal({ current: 0, total: 1, message: calls.first[:message], reset: true }, calls.first)
      assert_not_nil calls.first[:message]
      assert_equal({ current: 1, total: 1, message: calls.last[:message] }, calls.last)
      assert_not_nil calls.last[:message]
    end

    test 'apply: falseのときprogress_callbackは呼ばれない' do
      album = create_album
      ytmusic_album = create_ytmusic_album(album:)
      create_track_row(ytmusic_album:, album:)

      calls = []
      progress_callback = ->(**kwargs) { calls << kwargs }

      DistributionDate::YtmusicCollector.new(apply: false, out: StringIO.new, progress_callback:).run

      assert_empty calls
    end

    test 'collect_albumを直接呼び出すとrunを経由せずDBが更新されCollectOutcomeが返る' do
      album = create_album
      ytmusic_album = create_ytmusic_album(album:)
      track = create_track_row(ytmusic_album:, album:)
      video = FakeVideo.new(publish_date: Date.new(2026, 6, 29), upload_date: Date.new(2026, 6, 28),
                            release_date: nil, provided_by: nil)

      outcome = nil
      stub_const(YtMusic, :Video, stub_find_client { |_video_id| video }) do
        collector = DistributionDate::YtmusicCollector.new(apply: true, base_interval: 0, out: StringIO.new)
        outcome = collector.collect_album(ytmusic_album.id)
      end

      assert_equal :updated, outcome.status
      assert_equal 1, outcome.fetched_count
      assert_not_nil track.reload.video_fetched_at
      assert_equal Date.new(2026, 6, 30), ytmusic_album.reload.distributed_on
    end

    private

    # limit / workers / max_attempts / base_interval / all / only_missing は
    # DistributionDate::YtmusicCollectorのデフォルト値をそのまま使う。個別のテストで変えたい値だけを渡す。
    def run_collector(apply:, **)
      DistributionDate::YtmusicCollector.new(apply:, out: StringIO.new, **).run
    end

    # `YtMusic::Video.find` が一度でも呼ばれたら失敗させ、dry-run時にAPI呼び出しがないことを検証するためのfake。
    def raising_ytmusic_video_client
      stub_find_client { |_video_id| raise 'YtMusic::Video.find should not be called during dry-run' }
    end

    def stub_find_client(&)
      Class.new do
        define_singleton_method(:find, &)
      end
    end

    # ytmusic_albums.payload['tracks']の1要素分のFake。実際のYtmusicTrack.save_trackが
    # 参照するキー（title/url/video_id/playlist_id/track_number）に合わせている。
    def payload_track(video_id:, track_number:)
      {
        'title' => 'Track', 'url' => "https://music.youtube.com/watch?v=#{video_id}&list=pl-#{SecureRandom.hex(2)}",
        'video_id' => video_id, 'playlist_id' => "pl-#{SecureRandom.hex(2)}", 'track_number' => track_number
      }
    end

    # ytmusic_albums.distribution_track_metadataの1要素分のFake（既に取得済みの状態を再現する）。
    def distribution_metadata_entry(video_id:, track_number: 1, published_on: Date.new(2026, 6, 29))
      {
        'video_id' => video_id, 'track_number' => track_number, 'published_on' => published_on&.iso8601,
        'uploaded_on' => nil, 'original_released_on' => nil, 'provided_by' => nil, 'art_track' => false,
        'fetched_at' => Time.current.iso8601
      }
    end

    # collect_album内で発生する「fetch_video以外」の例外を再現するためのモンキーパッチ。
    # fetch_videoの例外はトラック単位で握りつぶす設計(残りのトラックの処理を継続する)なので、
    # アルバム単位のerror集計を検証するには、それとは別の失敗経路が必要になる。
    def with_recalculate_distribution_raising_for(target_id)
      original = YtmusicAlbum.instance_method(:recalculate_distribution!)
      YtmusicAlbum.define_method(:recalculate_distribution!) do
        raise 'boom' if id == target_id

        original.bind_call(self)
      end
      yield
    ensure
      YtmusicAlbum.define_method(:recalculate_distribution!, original)
    end

    def create_album
      Album.create!(jan_code: "ytmusic-collector-#{SecureRandom.hex(4)}")
    end

    def create_ytmusic_album(album: create_album, browse_id: "MPREb_collector_#{SecureRandom.hex(4)}")
      YtmusicAlbum.create!(album:, browse_id:, name: '配信日集計コレクタテスト用アルバム')
    end

    def create_track_row(ytmusic_album:, album:, video_id: "vid-#{SecureRandom.hex(4)}", video_fetched_at: nil)
      track = Track.create!(jan_code: album.jan_code, isrc: "ISRC#{SecureRandom.hex(6)}")
      YtmusicTrack.create!(
        album:, ytmusic_album:, track:,
        name: 'Track', video_id:, playlist_id: "pl-#{SecureRandom.hex(4)}",
        video_fetched_at:
      )
    end

    # all: false のとき対象外になる「配信日が確定済み」のアルバムを組み立てるための
    # published_on/art_track込みのトラック（recalculate_distribution!を直接呼べる状態にする）。
    def create_resolved_track(ytmusic_album:, album:, published_on: Date.new(2026, 6, 29))
      track = Track.create!(jan_code: album.jan_code, isrc: "ISRC#{SecureRandom.hex(6)}")
      YtmusicTrack.create!(
        album:, ytmusic_album:, track:,
        name: 'Track', video_id: "vid-#{SecureRandom.hex(4)}", playlist_id: "pl-#{SecureRandom.hex(4)}",
        art_track: true, published_on:, video_fetched_at: Time.current
      )
    end
  end
end
