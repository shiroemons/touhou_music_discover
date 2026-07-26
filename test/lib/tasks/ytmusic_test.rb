# frozen_string_literal: true

require 'test_helper'
require 'rake'

class YtmusicTaskTest < ActiveSupport::TestCase
  Rake::Task.define_task(:environment)
  load Rails.root.join('lib/tasks/ytmusic.rake')

  setup do
    Rake::Task['ytmusic:fetch_distribution_dates'].reenable
    Rake::Task['ytmusic:recalculate_distribution_dates'].reenable
    Rake::Task['ytmusic:album_tracks_save'].reenable
    Rake::Task['ytmusic:reset_distribution_dates'].reenable
  end

  test 'fetch_distribution_dates: ENV未指定のときデフォルト値でコレクタが渡る' do
    captured_kwargs = with_captured_collector_kwargs do
      Rake::Task['ytmusic:fetch_distribution_dates'].invoke
    end

    assert_equal(
      {
        apply: false, limit: nil, all: false, only_missing: true,
        max_attempts: DistributionDate::YtmusicCollector::DEFAULT_MAX_ATTEMPTS,
        request_interval: DistributionDate::YtmusicCollector::DEFAULT_REQUEST_INTERVAL
      },
      captured_kwargs
    )
  end

  test 'fetch_distribution_dates: APPLY=1でapply: trueが渡る' do
    captured_kwargs = with_env('APPLY' => '1') do
      with_captured_collector_kwargs { Rake::Task['ytmusic:fetch_distribution_dates'].invoke }
    end

    assert captured_kwargs[:apply]
  end

  test 'fetch_distribution_dates: LIMIT=5でlimit: 5が渡る' do
    captured_kwargs = with_env('LIMIT' => '5') do
      with_captured_collector_kwargs { Rake::Task['ytmusic:fetch_distribution_dates'].invoke }
    end

    assert_equal 5, captured_kwargs[:limit]
  end

  test 'fetch_distribution_dates: ALL=1でall: trueが渡る' do
    captured_kwargs = with_env('ALL' => '1') do
      with_captured_collector_kwargs { Rake::Task['ytmusic:fetch_distribution_dates'].invoke }
    end

    assert captured_kwargs[:all]
  end

  test 'fetch_distribution_dates: ONLY_MISSING=0でonly_missing: falseが渡る' do
    captured_kwargs = with_env('ONLY_MISSING' => '0') do
      with_captured_collector_kwargs { Rake::Task['ytmusic:fetch_distribution_dates'].invoke }
    end

    assert_not captured_kwargs[:only_missing]
  end

  test 'fetch_distribution_dates: MAX_ATTEMPTS=7でmax_attempts: 7が渡る' do
    captured_kwargs = with_env('MAX_ATTEMPTS' => '7') do
      with_captured_collector_kwargs { Rake::Task['ytmusic:fetch_distribution_dates'].invoke }
    end

    assert_equal 7, captured_kwargs[:max_attempts]
  end

  test 'fetch_distribution_dates: REQUEST_INTERVAL=0.5でrequest_interval: 0.5が渡る' do
    captured_kwargs = with_env('REQUEST_INTERVAL' => '0.5') do
      with_captured_collector_kwargs { Rake::Task['ytmusic:fetch_distribution_dates'].invoke }
    end

    assert_equal 0.5, captured_kwargs[:request_interval]
  end

  test 'recalculate_distribution_dates: ENV未指定では配信日未確定のアルバムだけ再集計される' do
    resolved_album = create_album
    resolved_ytmusic_album = create_ytmusic_album(album: resolved_album)
    create_resolved_track(ytmusic_album: resolved_ytmusic_album, album: resolved_album)
    resolved_ytmusic_album.recalculate_distribution!
    resolved_fetched_at_before = resolved_ytmusic_album.reload.distribution_fetched_at

    pending_album = create_album
    pending_ytmusic_album = create_ytmusic_album(album: pending_album)
    create_track_row(ytmusic_album: pending_ytmusic_album, album: pending_album)

    capture_io { Rake::Task['ytmusic:recalculate_distribution_dates'].invoke }

    assert_equal resolved_fetched_at_before, resolved_ytmusic_album.reload.distribution_fetched_at
    assert_not_nil pending_ytmusic_album.reload.distribution_fetched_at
  end

  test 'recalculate_distribution_dates: ALL=1では配信日確定済みのアルバムも再集計される' do
    resolved_album = create_album
    resolved_ytmusic_album = create_ytmusic_album(album: resolved_album)
    create_resolved_track(ytmusic_album: resolved_ytmusic_album, album: resolved_album)
    resolved_ytmusic_album.recalculate_distribution!
    resolved_fetched_at_before = resolved_ytmusic_album.reload.distribution_fetched_at

    travel_to(resolved_fetched_at_before + 1.hour) do
      with_env('ALL' => '1') do
        capture_io { Rake::Task['ytmusic:recalculate_distribution_dates'].invoke }
      end
    end

    assert_not_equal resolved_fetched_at_before, resolved_ytmusic_album.reload.distribution_fetched_at
  end

  test 'album_tracks_save: 配信日取得コレクタが例外を送出してもタスクは完了しトラックは影響を受けない' do
    album = create_album
    ytmusic_album = YtmusicAlbum.create!(album:, browse_id: "MPREb_task_#{SecureRandom.hex(4)}", name: 'Task Hook Test', total_tracks: 1)
    track = Track.create!(jan_code: album.jan_code, isrc: "ISRC#{SecureRandom.hex(6)}")
    ytmusic_track = YtmusicTrack.create!(
      album:, ytmusic_album:, track:,
      name: 'Task Hook Track', video_id: 'vid-task-hook', playlist_id: 'pl-task-hook'
    )

    called = false
    raising_new = lambda do |**_kwargs|
      called = true
      raise 'boom'
    end

    capture_io do
      with_singleton_method(DistributionDate::YtmusicCollector, :new, raising_new) do
        Rake::Task['ytmusic:album_tracks_save'].invoke
      end
    end

    assert called
    ytmusic_track.reload

    assert_equal 'Task Hook Track', ytmusic_track.name
    assert_equal 'vid-task-hook', ytmusic_track.video_id
    assert_nil ytmusic_track.video_fetched_at
  end

  test 'album_tracks_save: SKIP_DISTRIBUTION_DATES=1のときコレクタは生成されない' do
    called = false
    raising_new = lambda do |**_kwargs|
      called = true
      raise 'should not be called'
    end

    with_env('SKIP_DISTRIBUTION_DATES' => '1') do
      with_singleton_method(DistributionDate::YtmusicCollector, :new, raising_new) do
        Rake::Task['ytmusic:album_tracks_save'].invoke
      end
    end

    assert_not called
  end

  test 'reset_distribution_dates: dry-runでは対象件数を表示するだけで何も変更しない' do
    album = create_album
    ytmusic_album = create_ytmusic_album(album:)
    ytmusic_album.update!(distributed_on: Date.new(2026, 6, 30), distribution_source: 'art_track_mode', distribution_fetched_at: Time.current)
    track = create_track_row(ytmusic_album:, album:)
    track.update!(published_on: Date.new(2026, 6, 29), video_fetched_at: Time.current, art_track: true)

    out, = capture_io { Rake::Task['ytmusic:reset_distribution_dates'].invoke }

    assert_match(/対象アルバム数: 1 件/, out)
    assert_match(/対象トラック数: 1 件/, out)
    assert_not_nil ytmusic_album.reload.distributed_on
    assert_not_nil track.reload.video_fetched_at
  end

  test 'reset_distribution_dates: APPLY=1で対象カラムがすべて初期化される（art_trackはfalse）' do
    album = create_album
    ytmusic_album = create_ytmusic_album(album:)
    ytmusic_album.update!(
      distributed_on: Date.new(2026, 6, 30), youtube_published_on: Date.new(2026, 6, 29),
      original_released_on: Date.new(2026, 5, 4), distribution_source: 'art_track_mode',
      distribution_stats: { 'total_tracks' => 1 }, distribution_fetched_at: Time.current,
      distribution_track_metadata: [{ 'video_id' => 'v1' }]
    )
    track = create_track_row(ytmusic_album:, album:)
    track.update!(
      published_on: Date.new(2026, 6, 29), uploaded_on: Date.new(2026, 6, 28),
      original_released_on: Date.new(2026, 5, 4), provided_by: 'Rightsscale',
      video_metadata: { 'a' => 1 }, video_fetched_at: Time.current, art_track: true
    )

    with_env('APPLY' => '1') do
      capture_io { Rake::Task['ytmusic:reset_distribution_dates'].invoke }
    end

    ytmusic_album.reload

    assert_nil ytmusic_album.distributed_on
    assert_nil ytmusic_album.youtube_published_on
    assert_nil ytmusic_album.original_released_on
    assert_nil ytmusic_album.distribution_source
    assert_nil ytmusic_album.distribution_stats
    assert_nil ytmusic_album.distribution_fetched_at
    assert_nil ytmusic_album.distribution_track_metadata

    track.reload

    assert_nil track.published_on
    assert_nil track.uploaded_on
    assert_nil track.original_released_on
    assert_nil track.provided_by
    assert_nil track.video_metadata
    assert_nil track.video_fetched_at
    assert_not track.art_track
  end

  private

  def with_captured_collector_kwargs(&)
    captured_kwargs = nil
    fake_collector = Object.new
    fake_collector.define_singleton_method(:run) { {} }

    with_singleton_method(DistributionDate::YtmusicCollector, :new, lambda { |**kwargs|
      captured_kwargs = kwargs
      fake_collector
    }, &)

    captured_kwargs
  end

  def with_singleton_method(object, method_name, replacement)
    original_method = object.method(method_name)
    object.define_singleton_method(method_name, replacement)
    yield
  ensure
    object.define_singleton_method(method_name, original_method)
  end

  # 複数のENV変数をまとめて設定し、テスト終了後に元の値へ復元する。
  def with_env(overrides)
    previous = overrides.keys.index_with { |key| ENV.fetch(key, nil) }
    overrides.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

  def create_album
    Album.create!(jan_code: "ytmusic-task-#{SecureRandom.hex(4)}")
  end

  def create_ytmusic_album(album: create_album, browse_id: "MPREb_task_#{SecureRandom.hex(4)}")
    YtmusicAlbum.create!(album:, browse_id:, name: '配信日タスクテスト用アルバム')
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
