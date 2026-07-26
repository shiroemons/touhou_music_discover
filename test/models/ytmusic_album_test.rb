# frozen_string_literal: true

require 'test_helper'

class YtmusicAlbumTest < ActiveSupport::TestCase
  YtmusicApiAlbum = Struct.new(:title, :playlist_url, :track_total_count, :year, :degraded, :playable_track_count,
                               keyword_init: true) do
    def as_json(*)
      { 'title' => title, 'year' => year, 'artists' => [] }
    end

    def degraded?
      degraded
    end
  end

  test 'save_album reuses the row with the same album_id and browse_id when other attributes differ' do
    album = Album.create!(jan_code: "ytmusic-album-save-#{SecureRandom.hex(4)}")
    browse_id = "MPREb_#{SecureRandom.hex(4)}"

    assert_difference -> { YtmusicAlbum.unscoped.count }, 1 do
      YtmusicAlbum.save_album(album.id, browse_id, build_api_album(title: '東方猫鍵盤'))
    end

    assert_no_difference -> { YtmusicAlbum.unscoped.count } do
      @ytmusic_album = YtmusicAlbum.save_album(
        album.id,
        browse_id,
        build_api_album(title: '東方猫鍵盤 9', track_total_count: 12)
      )
    end

    assert_equal '東方猫鍵盤 9', @ytmusic_album.reload.name
    assert_equal 12, @ytmusic_album.total_tracks
    assert_equal "https://music.youtube.com/browse/#{browse_id}", @ytmusic_album.url
  end

  test 'save_album does not create a record when the album is degraded' do
    album = Album.create!(jan_code: "ytmusic-album-degraded-save-#{SecureRandom.hex(4)}")
    browse_id = "MPREb_#{SecureRandom.hex(4)}"

    result = nil
    assert_no_difference -> { YtmusicAlbum.unscoped.count } do
      result = YtmusicAlbum.save_album(album.id, browse_id, build_api_album(degraded: true))
    end

    assert_nil result
    assert_not YtmusicAlbum.unscoped.exists?(browse_id:)
  end

  test 'save_album creates a record as usual when the album is not degraded' do
    album = Album.create!(jan_code: "ytmusic-album-normal-save-#{SecureRandom.hex(4)}")
    browse_id = "MPREb_#{SecureRandom.hex(4)}"

    result = nil
    assert_difference -> { YtmusicAlbum.unscoped.count }, 1 do
      result = YtmusicAlbum.save_album(album.id, browse_id, build_api_album(title: '通常アルバム'))
    end

    assert_equal '通常アルバム', result.name
  end

  test 'update_album does not overwrite the payload when the album is degraded' do
    album = Album.create!(jan_code: "ytmusic-album-degraded-update-#{SecureRandom.hex(4)}")
    browse_id = "MPREb_#{SecureRandom.hex(4)}"
    ytmusic_album = YtmusicAlbum.save_album(album.id, browse_id, build_api_album(title: '既存アルバム'))
    original_payload = ytmusic_album.reload.payload

    result = ytmusic_album.update_album(
      build_api_album(title: '劣化アルバム', degraded: true),
      "https://music.youtube.com/browse/#{browse_id}"
    )

    assert_not result
    assert_equal original_payload, ytmusic_album.reload.payload
    assert_equal '既存アルバム', ytmusic_album.name
  end

  test 'update_album updates as usual when the album is not degraded' do
    album = Album.create!(jan_code: "ytmusic-album-normal-update-#{SecureRandom.hex(4)}")
    browse_id = "MPREb_#{SecureRandom.hex(4)}"
    ytmusic_album = YtmusicAlbum.save_album(album.id, browse_id, build_api_album(title: '更新前アルバム'))

    result = ytmusic_album.update_album(
      build_api_album(title: '更新後アルバム'),
      "https://music.youtube.com/browse/#{browse_id}"
    )

    assert result
    assert_equal '更新後アルバム', ytmusic_album.reload.name
  end

  test 'update_album rejects a fetch result with fewer playable tracks than the existing payload (regression guard)' do
    album = Album.create!(jan_code: "ytmusic-album-regression-decrease-#{SecureRandom.hex(4)}")
    browse_id = "MPREb_#{SecureRandom.hex(4)}"
    ytmusic_album = YtmusicAlbum.create!(album:, browse_id:, name: '既存アルバム', payload: playable_tracks_payload(10))

    result = ytmusic_album.update_album(
      build_api_album(title: '悪化アルバム', playable_track_count: 8),
      "https://music.youtube.com/browse/#{browse_id}"
    )

    assert_not result
    assert_equal '既存アルバム', ytmusic_album.reload.name
    assert_equal playable_tracks_payload(10), ytmusic_album.payload
  end

  test 'update_album updates when the playable track count stays the same (regression guard allows equal)' do
    album = Album.create!(jan_code: "ytmusic-album-regression-same-#{SecureRandom.hex(4)}")
    browse_id = "MPREb_#{SecureRandom.hex(4)}"
    ytmusic_album = YtmusicAlbum.create!(album:, browse_id:, name: '既存アルバム', payload: playable_tracks_payload(10))

    result = ytmusic_album.update_album(
      build_api_album(title: '更新後アルバム', playable_track_count: 10),
      "https://music.youtube.com/browse/#{browse_id}"
    )

    assert result
    assert_equal '更新後アルバム', ytmusic_album.reload.name
  end

  test 'update_album updates when the playable track count increases (regression guard allows improvement)' do
    album = Album.create!(jan_code: "ytmusic-album-regression-increase-#{SecureRandom.hex(4)}")
    browse_id = "MPREb_#{SecureRandom.hex(4)}"
    ytmusic_album = YtmusicAlbum.create!(album:, browse_id:, name: '既存アルバム', payload: playable_tracks_payload(10))

    result = ytmusic_album.update_album(
      build_api_album(title: '更新後アルバム', playable_track_count: 12),
      "https://music.youtube.com/browse/#{browse_id}"
    )

    assert result
    assert_equal '更新後アルバム', ytmusic_album.reload.name
  end

  test 'update_album updates even with few playable tracks when the existing payload has no tracks (regression guard does not apply)' do
    album = Album.create!(jan_code: "ytmusic-album-regression-empty-#{SecureRandom.hex(4)}")
    browse_id = "MPREb_#{SecureRandom.hex(4)}"
    ytmusic_album = YtmusicAlbum.create!(album:, browse_id:, name: '既存アルバム', payload: {})

    result = ytmusic_album.update_album(
      build_api_album(title: '更新後アルバム', playable_track_count: 1),
      "https://music.youtube.com/browse/#{browse_id}"
    )

    assert result
    assert_equal '更新後アルバム', ytmusic_album.reload.name
  end

  test 'reports progress while fetching YouTube Music albums' do
    album = Album.create!(jan_code: "ytmusic-progress-#{SecureRandom.hex(4)}")
    updates = []
    processed_albums = []

    with_ytmusic_album_processors(->(processed_album) { processed_albums << processed_album }) do
      with_ytmusic_album_url_updater do
        Album.unscoped.where(id: album.id).scoping do
          YtmusicAlbum.fetch_albums(progress_callback: ->(**attrs) { updates << attrs })
        end
      end
    end

    assert_equal [album], processed_albums
    assert_equal(
      { current: 0, total: 1, message: 'YouTube Musicアルバム候補を処理しています', reset: true },
      updates.first
    )
    assert_equal 1, updates.last.fetch(:current)
    assert_equal 1, updates.last.fetch(:total)
    assert_equal "YouTube Musicアルバム候補を処理しています: #{album.jan_code}", updates.last.fetch(:message)
  end

  test 'recalculate_distribution!: Art Trackの最頻値が採用されdistributed_onが最頻値+1日になる' do
    album = create_distribution_album
    ytmusic_album = create_distribution_ytmusic_album(album)
    3.times { create_distribution_track(ytmusic_album:, album:, art_track: true, published_on: Date.new(2026, 6, 29)) }
    create_distribution_track(ytmusic_album:, album:, art_track: false, published_on: Date.new(2021, 10, 16))

    ytmusic_album.recalculate_distribution!

    assert_equal 'art_track_mode', ytmusic_album.distribution_source
    assert_equal Date.new(2026, 6, 29), ytmusic_album.youtube_published_on
    assert_equal Date.new(2026, 6, 30), ytmusic_album.distributed_on
    assert_equal 4, ytmusic_album.distribution_stats['total_tracks']
    assert_equal 3, ytmusic_album.distribution_stats['art_tracks']
  end

  test 'recalculate_distribution!: Art Trackに混じった古いMVは集計から除外されexcluded_video_idsに記録される' do
    album = create_distribution_album
    ytmusic_album = create_distribution_ytmusic_album(album)
    2.times { create_distribution_track(ytmusic_album:, album:, art_track: true, published_on: Date.new(2026, 6, 29)) }
    old_mv = create_distribution_track(ytmusic_album:, album:, art_track: false, published_on: Date.new(2021, 10, 16))

    ytmusic_album.recalculate_distribution!

    assert_includes ytmusic_album.distribution_stats['excluded_video_ids'], old_mv.video_id
  end

  test 'recalculate_distribution!: 最頻値が同数タイのとき古い方が選ばれtie_breakがtrueになる' do
    album = create_distribution_album
    ytmusic_album = create_distribution_ytmusic_album(album)
    create_distribution_track(ytmusic_album:, album:, art_track: true, published_on: Date.new(2026, 7, 1))
    create_distribution_track(ytmusic_album:, album:, art_track: true, published_on: Date.new(2026, 6, 30))

    ytmusic_album.recalculate_distribution!

    assert_equal Date.new(2026, 6, 30), ytmusic_album.youtube_published_on
    assert_equal Date.new(2026, 7, 1), ytmusic_album.distributed_on
    assert ytmusic_album.distribution_stats['tie_break']
  end

  test 'recalculate_distribution!: Art Trackが0件のとき全トラックへフォールバックしall_track_modeになる' do
    album = create_distribution_album
    ytmusic_album = create_distribution_ytmusic_album(album)
    2.times { create_distribution_track(ytmusic_album:, album:, art_track: false, published_on: Date.new(2026, 6, 29)) }

    ytmusic_album.recalculate_distribution!

    assert_equal 'all_track_mode', ytmusic_album.distribution_source
    assert_equal Date.new(2026, 6, 29), ytmusic_album.youtube_published_on
  end

  test 'recalculate_distribution!: 候補が1件のときsingle_trackになる' do
    album = create_distribution_album
    ytmusic_album = create_distribution_ytmusic_album(album)
    create_distribution_track(ytmusic_album:, album:, art_track: true, published_on: Date.new(2026, 6, 29))

    ytmusic_album.recalculate_distribution!

    assert_equal 'single_track', ytmusic_album.distribution_source
  end

  test 'recalculate_distribution!: published_onが1件も無いときfailedになり日付カラムはnilのままだがstatsとfetched_atは記録される' do
    album = create_distribution_album
    ytmusic_album = create_distribution_ytmusic_album(album)
    create_distribution_track(ytmusic_album:, album:, art_track: false, published_on: nil)

    ytmusic_album.recalculate_distribution!

    assert_equal 'failed', ytmusic_album.distribution_source
    assert_nil ytmusic_album.distributed_on
    assert_nil ytmusic_album.youtube_published_on
    assert_nil ytmusic_album.original_released_on
    assert_not_nil ytmusic_album.distribution_stats
    assert_not_nil ytmusic_album.distribution_fetched_at
  end

  test 'recalculate_distribution!: original_released_onが候補トラックの最頻値ルールで算出される' do
    album = create_distribution_album
    ytmusic_album = create_distribution_ytmusic_album(album)
    2.times do
      create_distribution_track(
        ytmusic_album:, album:, art_track: true,
        published_on: Date.new(2026, 6, 29), original_released_on: Date.new(2026, 5, 4)
      )
    end
    create_distribution_track(
      ytmusic_album:, album:, art_track: true,
      published_on: Date.new(2026, 6, 29), original_released_on: Date.new(2021, 1, 1)
    )

    ytmusic_album.recalculate_distribution!

    assert_equal Date.new(2026, 5, 4), ytmusic_album.original_released_on
  end

  test 'recalculate_distribution!: distribution_track_metadataがあればtrack行が無くてもそれを集計元にできる（source_of_truth: payload）' do
    album = create_distribution_album
    ytmusic_album = create_distribution_ytmusic_album(album)
    ytmusic_album.update!(distribution_track_metadata: [
                            distribution_metadata_entry(video_id: 'v1', art_track: true, published_on: Date.new(2026, 6, 29)),
                            distribution_metadata_entry(video_id: 'v2', art_track: true, published_on: Date.new(2026, 6, 29))
                          ])

    ytmusic_album.recalculate_distribution!

    assert_equal 'art_track_mode', ytmusic_album.distribution_source
    assert_equal Date.new(2026, 6, 29), ytmusic_album.youtube_published_on
    assert_equal Date.new(2026, 6, 30), ytmusic_album.distributed_on
    assert_equal 'payload', ytmusic_album.distribution_stats['source_of_truth']
    assert_equal 2, ytmusic_album.distribution_stats['total_tracks']
    assert_equal 0, ytmusic_album.ytmusic_tracks.count
  end

  test 'recalculate_distribution!: distribution_track_metadataが無ければtrack行から集計する（source_of_truth: track_rows、後方互換）' do
    album = create_distribution_album
    ytmusic_album = create_distribution_ytmusic_album(album)
    create_distribution_track(ytmusic_album:, album:, art_track: true, published_on: Date.new(2026, 6, 29))

    ytmusic_album.recalculate_distribution!

    assert_equal 'track_rows', ytmusic_album.distribution_stats['source_of_truth']
  end

  test 'distribution_missingスコープはdistributed_onがnilまたはdistribution_sourceがfailedの行を返す' do
    not_recalculated = create_distribution_ytmusic_album(create_distribution_album)

    failed_album = create_distribution_album
    failed = create_distribution_ytmusic_album(failed_album)
    create_distribution_track(ytmusic_album: failed, album: failed_album, art_track: false, published_on: nil)
    failed.recalculate_distribution!

    succeeded_album = create_distribution_album
    succeeded = create_distribution_ytmusic_album(succeeded_album)
    create_distribution_track(ytmusic_album: succeeded, album: succeeded_album, art_track: true, published_on: Date.new(2026, 6, 29))
    succeeded.recalculate_distribution!

    missing_ids = YtmusicAlbum.unscoped.distribution_missing.pluck(:id)

    assert_includes missing_ids, not_recalculated.id
    assert_includes missing_ids, failed.id
    assert_not_includes missing_ids, succeeded.id
  end

  test 'recalculate_distribution!: 全動画が縮退したアルバムはdistribution_sourceがdegradedになりfailedにならない' do
    album = create_distribution_album
    ytmusic_album = create_distribution_ytmusic_album(album)
    ytmusic_album.update!(distribution_track_metadata: [
                            distribution_metadata_entry(video_id: 'v1', art_track: false, published_on: nil, degraded: true),
                            distribution_metadata_entry(video_id: 'v2', art_track: false, published_on: nil, degraded: true)
                          ])

    ytmusic_album.recalculate_distribution!

    assert_equal 'degraded', ytmusic_album.distribution_source
    assert_nil ytmusic_album.distributed_on
    assert_equal 2, ytmusic_album.distribution_stats['degraded_videos']
  end

  test 'recalculate_distribution!: 一部だけ縮退したアルバムはdistributed_onが算出されてもdistribution_missingに含まれる' do
    album = create_distribution_album
    ytmusic_album = create_distribution_ytmusic_album(album)
    ytmusic_album.update!(distribution_track_metadata: [
                            distribution_metadata_entry(video_id: 'v1', art_track: true, published_on: Date.new(2026, 6, 29)),
                            distribution_metadata_entry(video_id: 'v2', art_track: false, published_on: nil, degraded: true)
                          ])

    ytmusic_album.recalculate_distribution!

    assert_not_nil ytmusic_album.distributed_on
    assert_includes YtmusicAlbum.unscoped.distribution_missing.pluck(:id), ytmusic_album.id
  end

  test 'recalculate_distribution!: 縮退が解消されたアルバムはdistribution_missingから外れる' do
    album = create_distribution_album
    ytmusic_album = create_distribution_ytmusic_album(album)
    ytmusic_album.update!(distribution_track_metadata: [
                            distribution_metadata_entry(video_id: 'v1', art_track: true, published_on: Date.new(2026, 6, 29), degraded: false),
                            distribution_metadata_entry(video_id: 'v2', art_track: true, published_on: Date.new(2026, 6, 29), degraded: false)
                          ])

    ytmusic_album.recalculate_distribution!

    assert_not_includes YtmusicAlbum.unscoped.distribution_missing.pluck(:id), ytmusic_album.id
  end

  private

  def create_distribution_album
    Album.create!(jan_code: "ytmusic-dist-#{SecureRandom.hex(4)}")
  end

  def create_distribution_ytmusic_album(album)
    YtmusicAlbum.create!(album:, browse_id: "MPREb_dist_#{SecureRandom.hex(4)}", name: '配信日集計テスト用アルバム')
  end

  def create_distribution_track(ytmusic_album:, album:, art_track:, published_on:, original_released_on: nil)
    track = Track.create!(jan_code: album.jan_code, isrc: "ISRC#{SecureRandom.hex(6)}")
    YtmusicTrack.create!(
      album:, ytmusic_album:, track:,
      name: 'Track', video_id: "vid-#{SecureRandom.hex(4)}", playlist_id: "pl-#{SecureRandom.hex(4)}",
      art_track:, published_on:, original_released_on:, video_fetched_at: Time.current
    )
  end

  # distribution_track_metadataの1要素分のFake。DistributionDate::YtmusicCollectorが
  # 実際に保存する形式（文字列キー、日付はISO8601文字列）に合わせている。
  # degraded: trueのときは、build_metadata_entryが縮退時にfetched_atをnilのまま保存する
  # 実装に合わせてfetched_atをnilにする。
  # rubocop:disable Metrics/ParameterLists -- テストヘルパーとして各テストが個別に指定したい値をそのまま
  # キーワード引数で公開しているため、オプションハッシュへの集約はしない。
  def distribution_metadata_entry(video_id:, art_track:, published_on:, track_number: 1, original_released_on: nil, degraded: false)
    {
      'video_id' => video_id,
      'track_number' => track_number,
      'published_on' => published_on&.iso8601,
      'uploaded_on' => nil,
      'original_released_on' => original_released_on&.iso8601,
      'provided_by' => art_track ? 'Rightsscale' : nil,
      'art_track' => art_track,
      'degraded' => degraded,
      'fetched_at' => degraded ? nil : Time.current.iso8601
    }
  end
  # rubocop:enable Metrics/ParameterLists

  def playable_tracks_payload(count)
    { 'tracks' => Array.new(count) { |i| { 'video_id' => "v#{i}", 'track_number' => i + 1 } } }
  end

  def build_api_album(**attributes)
    YtmusicApiAlbum.new(
      title: 'YouTube Music Album',
      playlist_url: 'https://music.youtube.com/playlist?list=test',
      track_total_count: 10,
      year: '2026',
      degraded: false,
      playable_track_count: attributes[:degraded] ? 0 : 10,
      **attributes
    )
  end

  def with_ytmusic_album_processors(processor)
    singleton_class = YtmusicAlbum.singleton_class
    original_spotify_method = YtmusicAlbum.method(:process_album_with_spotify)
    original_apple_music_method = YtmusicAlbum.method(:process_album_with_apple_music)

    singleton_class.define_method(:process_album_with_spotify) { |album| processor.call(album) }
    singleton_class.define_method(:process_album_with_apple_music) { |_album| nil }
    yield
  ensure
    singleton_class.define_method(:process_album_with_spotify, original_spotify_method)
    singleton_class.define_method(:process_album_with_apple_music, original_apple_music_method)
  end

  def with_ytmusic_album_url_updater
    singleton_class = YtmusicAlbum.singleton_class
    original_method = YtmusicAlbum.method(:update_ytmusic_album_urls)

    singleton_class.define_method(:update_ytmusic_album_urls) { |**_kwargs| nil }
    yield
  ensure
    singleton_class.define_method(:update_ytmusic_album_urls, original_method)
  end
end
