# frozen_string_literal: true

require 'test_helper'

module Dedupe
  class PlatformRecordsTest < ActiveSupport::TestCase
    # テストデータはテーブル全体が重複だらけになるため、比率・件数の安全装置は明示的に緩めておき、
    # 安全装置そのものを検証するテストだけ閾値を絞る。
    test 'dry-runでは1行も削除しない' do
      duplicates = create_apple_music_album_duplicates
      result = nil

      assert_no_difference ['AppleMusicAlbum.unscoped.count', 'AppleMusicTrack.unscoped.count'] do
        result = run_dedupe(apply: false)
      end

      assert_not result[:applied]
      assert_equal 0, result[:deleted_count]
      assert_equal 1, result[:tables]['AppleMusicAlbum'][:deletions]
      assert AppleMusicAlbum.unscoped.exists?(id: duplicates[:keeper].id)
      assert AppleMusicAlbum.unscoped.exists?(id: duplicates[:loser].id)
    end

    test 'applyすると最古の行が残り重複行だけが削除される' do
      album = create_album
      apple_music_id = "dedupe-am-#{SecureRandom.hex(4)}"
      oldest = middle = newest = nil
      without_unique_index(:apple_music_albums, 'index_apple_music_albums_on_apple_music_id') do
        oldest = create_apple_music_album(album:, apple_music_id:, created_at: 3.days.ago)
        middle = create_apple_music_album(album:, apple_music_id:, created_at: 2.days.ago)
        newest = create_apple_music_album(album:, apple_music_id:, created_at: 1.day.ago)
      end

      result = run_dedupe(apply: true)

      assert result[:applied]
      assert_equal 2, result[:deleted_count]
      assert AppleMusicAlbum.unscoped.exists?(id: oldest.id)
      assert_not AppleMusicAlbum.unscoped.exists?(id: middle.id)
      assert_not AppleMusicAlbum.unscoped.exists?(id: newest.id)
      assert_equal 1, AppleMusicAlbum.unscoped.where(apple_music_id:).count
    end

    test 'SpotifyTrackAudioFeatureは最新の行が残る' do
      spotify_track = create_spotify_track_with_album
      older = newer = nil
      without_unique_index(:spotify_track_audio_features, 'index_spotify_track_audio_features_on_spotify_track_id') do
        older = create_spotify_track_audio_feature(spotify_track:, tempo: 100.0, created_at: 2.days.ago)
        newer = create_spotify_track_audio_feature(spotify_track:, tempo: 130.0, created_at: 1.day.ago)
      end

      run_dedupe(apply: true)

      assert SpotifyTrackAudioFeature.exists?(id: newer.id)
      assert_not SpotifyTrackAudioFeature.exists?(id: older.id)
      assert_in_delta 130.0, SpotifyTrackAudioFeature.find(newer.id).tempo
    end

    test 'LineMusicTrackは最新の行が残る' do
      line_music_album = create_line_music_album
      track = create_track(line_music_album.album)
      line_music_id = "dedupe-lm-#{SecureRandom.hex(4)}"
      older = newer = nil
      without_unique_index(:line_music_tracks, 'index_line_music_tracks_on_lm_album_id_and_lm_id') do
        older = create_line_music_track(line_music_album:, track:, line_music_id:, created_at: 2.days.ago)
        newer = create_line_music_track(line_music_album:, track:, line_music_id:, created_at: 1.day.ago)
      end

      run_dedupe(apply: true)

      assert LineMusicTrack.unscoped.exists?(id: newer.id)
      assert_not LineMusicTrack.unscoped.exists?(id: older.id)
    end

    test 'YtmusicTrackはalbum.payloadに載っているvideo_idの行が残る（最古が一致するケース）' do
      fixture = create_ytmusic_track_duplicates(payload_video_ids: :older)

      run_dedupe(apply: true)

      assert YtmusicTrack.unscoped.exists?(id: fixture[:older].id)
      assert_not YtmusicTrack.unscoped.exists?(id: fixture[:newer].id)
    end

    test 'YtmusicTrackはalbum.payloadに載っているvideo_idの行が残る（最新が一致するケース）' do
      fixture = create_ytmusic_track_duplicates(payload_video_ids: :newer)

      run_dedupe(apply: true)

      assert YtmusicTrack.unscoped.exists?(id: fixture[:newer].id)
      assert_not YtmusicTrack.unscoped.exists?(id: fixture[:older].id)
    end

    test 'YtmusicTrackはalbum.payloadに一致するvideo_idがない場合は最古が残る' do
      fixture = create_ytmusic_track_duplicates(payload_video_ids: :none)

      run_dedupe(apply: true)

      assert YtmusicTrack.unscoped.exists?(id: fixture[:older].id)
      assert_not YtmusicTrack.unscoped.exists?(id: fixture[:newer].id)
    end

    test 'YtmusicTrackはalbum.payloadに複数一致する場合は最古が残る' do
      fixture = create_ytmusic_track_duplicates(payload_video_ids: :both)

      run_dedupe(apply: true)

      assert YtmusicTrack.unscoped.exists?(id: fixture[:older].id)
      assert_not YtmusicTrack.unscoped.exists?(id: fixture[:newer].id)
    end

    test 'AppleMusicAlbumは削除前に最新の属性がkeeperへマージされる' do
      fixture = create_apple_music_album_merge_target

      run_dedupe(apply: true)
      keeper = AppleMusicAlbum.unscoped.find(fixture[:keeper].id)

      assert_equal 'New Name', keeper.name
      assert_equal 'https://example.com/new', keeper.url
      # loser 側が nil の列は「情報がない」だけなので keeper の値を残す。
      assert_equal Date.new(2020, 1, 1), keeper.release_date
    end

    test 'AppleMusicAlbumの属性マージは削除ログに記録される' do
      fixture = create_apple_music_album_merge_target

      result = run_dedupe(apply: true)
      rows = Pathname.new(result[:log_path]).readlines.map { |line| JSON.parse(line) }
      merge_row = rows.find { |row| row['type'] == 'merge' && row['id'] == fixture[:keeper].id }

      assert_equal 'apple_music_albums', merge_row['table']
      assert_equal fixture[:loser].id, merge_row['source_id']
      assert_equal({ 'from' => 'Old Name', 'to' => 'New Name' }, merge_row['changes']['name'])
      assert_equal 1, result[:total_merges]
      assert_equal 1, result[:tables]['AppleMusicAlbum'][:merges]
    end

    test 'YtmusicAlbumも削除前に最新の属性がkeeperへマージされる' do
      album = create_album
      browse_id = "dedupe-yta-#{SecureRandom.hex(4)}"
      keeper = nil
      without_unique_index(:ytmusic_albums, 'index_ytmusic_albums_on_album_id_and_browse_id') do
        keeper = create_ytmusic_album(album:, browse_id:, name: 'Old Name', created_at: 2.days.ago)
        create_ytmusic_album(album:, browse_id:, name: 'New Name', created_at: 1.day.ago)
      end

      result = run_dedupe(apply: true)

      assert_equal 'New Name', YtmusicAlbum.unscoped.find(keeper.id).name
      assert_equal 1, result[:tables]['YtmusicAlbum'][:merges]
    end

    test 'マージ対象外のテーブルでは最新の属性がkeeperへマージされない' do
      album = create_album
      apple_music_album = create_apple_music_album(album:, apple_music_id: "dedupe-am-#{SecureRandom.hex(4)}")
      track = create_track(album)
      keeper = nil
      without_unique_index(:apple_music_tracks, 'index_apple_music_tracks_on_am_album_id_and_am_id') do
        keeper = create_apple_music_track(apple_music_album:, track:, apple_music_id: 'track-merge',
                                          name: 'Old Name', created_at: 2.days.ago)
        create_apple_music_track(apple_music_album:, track:, apple_music_id: 'track-merge',
                                 name: 'New Name', created_at: 1.day.ago)
      end

      result = run_dedupe(apply: true)
      rows = Pathname.new(result[:log_path]).readlines.map { |line| JSON.parse(line) }

      assert_equal 'Old Name', AppleMusicTrack.unscoped.find(keeper.id).name
      assert_equal 0, result[:tables]['AppleMusicTrack'][:merges]
      assert_empty(rows.select { |row| row['type'] == 'merge' && row['table'] == 'apple_music_tracks' })
    end

    test 'max_deletionsを超える場合はapplyでも中断して1行も削除しない' do
      create_apple_music_album_duplicates(loser_count: 2)
      result = nil

      assert_no_difference 'AppleMusicAlbum.unscoped.count' do
        result = run_dedupe(apply: true, max_deletions: 1)
      end

      assert result[:aborted]
      assert_not result[:applied]
      assert_equal 0, result[:deleted_count]
      assert_equal 1, result[:abort_reasons].size
    end

    test 'max_ratioを超える場合はapplyでも中断して1行も削除しない' do
      create_apple_music_album_duplicates
      result = nil

      assert_no_difference 'AppleMusicAlbum.unscoped.count' do
        result = run_dedupe(apply: true, max_ratio: 0.05)
      end

      assert result[:aborted]
      assert_equal 0, result[:deleted_count]
    end

    test '親の重複削除時に子はkeeperへ付け替えられ、同じ一意キーの子は削除される' do
      fixture = create_apple_music_album_with_children

      result = run_dedupe(apply: true)

      assert_equal 1, result[:tables]['AppleMusicAlbum'][:reassignments]
      assert_not AppleMusicAlbum.unscoped.exists?(id: fixture[:loser].id)
      assert AppleMusicTrack.unscoped.exists?(id: fixture[:kept_child].id)
      assert_not AppleMusicTrack.unscoped.exists?(id: fixture[:duplicated_child].id)
      assert_equal fixture[:keeper].id, AppleMusicTrack.unscoped.find(fixture[:moved_child].id).apple_music_album_id
    end

    test '連鎖削除された子の件数が結果に含まれる' do
      fixture = create_apple_music_album_with_children

      result = run_dedupe(apply: true)

      # duplicated_child だけが dependent: :destroy で道連れになる。
      assert_equal 1, result[:tables]['AppleMusicAlbum'][:cascaded]
      assert_equal 1, result[:cascaded_deleted_count]
      assert_equal result[:total_direct_deletions] + result[:total_cascaded_deletions], result[:total_deletions]
      assert_not AppleMusicTrack.unscoped.exists?(id: fixture[:duplicated_child].id)
    end

    test '削除ログには連鎖削除された子の行も記録される' do
      fixture = create_apple_music_album_with_children

      result = run_dedupe(apply: true)
      rows = Pathname.new(result[:log_path]).readlines.map { |line| JSON.parse(line) }
      cascaded_row = rows.find { |row| row['id'] == fixture[:duplicated_child].id }

      assert_equal 'cascaded', cascaded_row['type']
      assert_equal 'apple_music_tracks', cascaded_row['table']
      assert_equal({ 'apple_music_id' => 'track-shared' }, cascaded_row['key'])
      assert_equal({ 'table' => 'apple_music_albums', 'id' => fixture[:loser].id }, cascaded_row['cascaded_from'])
      assert_not AppleMusicTrack.unscoped.exists?(id: cascaded_row['id'])
    end

    test '連鎖削除だけでmax_deletionsを超える場合はapplyでも中断して1行も削除しない' do
      fixture = create_apple_music_album_with_children
      result = nil

      # 直接削除1件のみなら上限内だが、連鎖削除1件を合算すると上限を超える。
      assert_no_difference ['AppleMusicAlbum.unscoped.count', 'AppleMusicTrack.unscoped.count'] do
        result = run_dedupe(apply: true, max_deletions: 1)
      end

      assert result[:aborted]
      assert_equal 0, result[:deleted_count]
      assert_match(/直接 1 件 \+ 連鎖 1 件 = 合計 2 件/, result[:abort_reasons].first)
      assert AppleMusicTrack.unscoped.exists?(id: fixture[:duplicated_child].id)
    end

    test '子テーブルへの連鎖削除比率が上限を超える場合はapplyでも中断する' do
      fixture = create_apple_music_album_with_children
      cascaded_ratio = 1.0 / AppleMusicTrack.unscoped.count
      result = nil

      # 子テーブル側の連鎖削除比率が独立した違反として報告されることを確かめる。
      assert_no_difference ['AppleMusicAlbum.unscoped.count', 'AppleMusicTrack.unscoped.count'] do
        result = run_dedupe(apply: true, max_ratio: cascaded_ratio / 2)
      end

      assert result[:aborted]
      assert_equal 0, result[:deleted_count]
      assert(result[:abort_reasons].any? { |reason| reason.include?('AppleMusicTrack への連鎖削除予定比率') })
      assert AppleMusicTrack.unscoped.exists?(id: fixture[:duplicated_child].id)
    end

    test 'SpotifyTrackの重複削除時にaudio featureがkeeperへ付け替えられる' do
      spotify_album = create_spotify_album
      track = create_track(spotify_album.album)
      spotify_id = "dedupe-sp-#{SecureRandom.hex(4)}"
      keeper = loser = nil
      without_unique_index(:spotify_tracks, 'index_spotify_tracks_on_spotify_album_id_and_spotify_id') do
        keeper = create_spotify_track(spotify_album:, track:, spotify_id:, created_at: 2.days.ago)
        loser = create_spotify_track(spotify_album:, track:, spotify_id:, created_at: 1.day.ago)
      end
      audio_feature = create_spotify_track_audio_feature(spotify_track: loser, tempo: 120.0, created_at: 1.day.ago)

      result = run_dedupe(apply: true)

      assert_equal 1, result[:tables]['SpotifyTrack'][:reassignments]
      assert_not SpotifyTrack.unscoped.exists?(id: loser.id)
      assert_equal keeper.id, SpotifyTrackAudioFeature.find(audio_feature.id).spotify_track_id
    end

    test '実削除後はJSON Lines形式の削除ログが出力される' do
      duplicates = create_apple_music_album_duplicates

      result = run_dedupe(apply: true)
      log_path = Pathname.new(result[:log_path])

      assert_predicate log_path, :exist?
      # ログは追記式で、並列実行中の他テストの削除行も混ざりうるため、自テストの削除行を探して検証する。
      deleted_row = log_path.readlines.map { |line| JSON.parse(line) }.find { |row| row['id'] == duplicates[:loser].id }

      assert_equal 'apple_music_albums', deleted_row['table']
      assert_equal duplicates[:keeper].id, deleted_row['kept_id']
      assert_equal({ 'apple_music_id' => duplicates[:apple_music_id] }, deleted_row['key'])
      assert_predicate deleted_row['created_at'], :present?
    end

    test '2回目の実行では削除対象が0件になる' do
      create_apple_music_album_duplicates(loser_count: 2)

      first_result = run_dedupe(apply: true)

      assert_equal 2, first_result[:deleted_count]

      second_result = nil

      assert_no_difference 'AppleMusicAlbum.unscoped.count' do
        second_result = run_dedupe(apply: true)
      end

      assert_equal 0, second_result[:total_deletions]
      assert_equal 0, second_result[:deleted_count]
      assert_nil second_result[:log_path]
    end

    private

    def run_dedupe(apply:, max_deletions: 1000, max_ratio: 1.0)
      PlatformRecords.new(apply:, max_deletions:, max_ratio:, out: StringIO.new).run
    end

    # unique index 下で重複行を意図的に作るためのテスト専用ヘルパー。
    # PostgreSQLのDDLはトランザクション対応で、各テストはトランザクション内で実行されロールバックされるため、
    # ここで外したindexはテスト終了時に自動的に復元される（明示的なteardownは不要）。
    def without_unique_index(table, index_name)
      ActiveRecord::Base.connection.remove_index(table, name: index_name)
      yield
    end

    # keeper（最古）1件と loser を loser_count 件持つ AppleMusicAlbum の重複を作る。
    def create_apple_music_album_duplicates(loser_count: 1)
      album = create_album
      apple_music_id = "dedupe-am-#{SecureRandom.hex(4)}"
      keeper = nil
      losers = []

      without_unique_index(:apple_music_albums, 'index_apple_music_albums_on_apple_music_id') do
        keeper = create_apple_music_album(album:, apple_music_id:, created_at: (loser_count + 1).days.ago)
        losers = Array.new(loser_count) do |index|
          create_apple_music_album(album:, apple_music_id:, created_at: (loser_count - index).days.ago)
        end
      end

      { album:, apple_music_id:, keeper:, loser: losers.first, losers: }
    end

    # keeper / loser の AppleMusicAlbum に、付け替えられる子1件と連鎖削除される子1件をぶら下げる。
    def create_apple_music_album_with_children
      duplicates = create_apple_music_album_duplicates
      keeper = duplicates[:keeper]
      loser = duplicates[:loser]
      album = duplicates[:album]

      shared_track = create_track(album)
      only_loser_track = create_track(album)

      duplicates.merge(
        kept_child: create_apple_music_track(apple_music_album: keeper, track: shared_track, apple_music_id: 'track-shared'),
        duplicated_child: create_apple_music_track(apple_music_album: loser, track: shared_track, apple_music_id: 'track-shared'),
        moved_child: create_apple_music_track(apple_music_album: loser, track: only_loser_track, apple_music_id: 'track-only-loser')
      )
    end

    # keeper（最古）と loser（最新）で name / url / release_date の埋まり方が違う AppleMusicAlbum の重複を作る。
    def create_apple_music_album_merge_target
      album = create_album
      apple_music_id = "dedupe-am-#{SecureRandom.hex(4)}"
      keeper = loser = nil

      without_unique_index(:apple_music_albums, 'index_apple_music_albums_on_apple_music_id') do
        keeper = create_apple_music_album(album:, apple_music_id:, name: 'Old Name',
                                          release_date: Date.new(2020, 1, 1), created_at: 2.days.ago)
        loser = create_apple_music_album(album:, apple_music_id:, name: 'New Name',
                                         url: 'https://example.com/new', created_at: 1.day.ago)
      end

      { album:, apple_music_id:, keeper:, loser: }
    end

    # 同じ track を指す YtmusicTrack の重複を作る。
    # payload_video_ids で「親アルバムの payload にどちらの video_id を載せるか」を切り替える。
    def create_ytmusic_track_duplicates(payload_video_ids:)
      album = create_album
      track = create_track(album)
      older_video_id = "dedupe-video-old-#{SecureRandom.hex(4)}"
      newer_video_id = "dedupe-video-new-#{SecureRandom.hex(4)}"
      video_ids = {
        older: [older_video_id], newer: [newer_video_id],
        none: [], both: [older_video_id, newer_video_id]
      }.fetch(payload_video_ids)
      ytmusic_album = create_ytmusic_album(album:, video_ids:)
      older = newer = nil

      without_unique_index(:ytmusic_tracks, 'index_ytmusic_tracks_on_ytmusic_album_id_and_track_id') do
        older = create_ytmusic_track(ytmusic_album:, track:, video_id: older_video_id, created_at: 2.days.ago)
        newer = create_ytmusic_track(ytmusic_album:, track:, video_id: newer_video_id, created_at: 1.day.ago)
      end

      { ytmusic_album:, older:, newer: }
    end

    # 「どの行を残すか」は created_at で決まるため、Railsが自動設定した値を上書きして順序を固定する。
    # rubocop:disable Rails/SkipsModelValidations
    def overwrite_created_at(record, created_at)
      record.update_columns(created_at:)
    end
    # rubocop:enable Rails/SkipsModelValidations

    def create_album
      Album.create!(jan_code: "dedupe-#{SecureRandom.hex(6)}")
    end

    def create_track(album)
      Track.create!(album:, isrc: "JPDD#{SecureRandom.alphanumeric(8).upcase}")
    end

    # name / url / release_date などを上書きしたい場合は attributes に渡す。
    def create_apple_music_album(album:, apple_music_id:, created_at: Time.current, **attributes)
      AppleMusicAlbum.create!(
        album:,
        apple_music_id:,
        name: 'Dedupe Apple Music Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        **attributes
      ).tap { |record| overwrite_created_at(record, created_at) }
    end

    def create_apple_music_track(apple_music_album:, track:, apple_music_id:, name: 'Dedupe Apple Music Track',
                                 created_at: Time.current)
      AppleMusicTrack.create!(
        album: apple_music_album.album,
        apple_music_album:,
        track:,
        apple_music_id:,
        name:,
        label: Album::TOUHOU_MUSIC_LABEL
      ).tap { |record| overwrite_created_at(record, created_at) }
    end

    def create_line_music_album
      album = create_album
      LineMusicAlbum.create!(
        album:,
        line_music_id: "dedupe-lma-#{SecureRandom.hex(4)}",
        name: 'Dedupe LINE MUSIC Album'
      )
    end

    def create_line_music_track(line_music_album:, track:, line_music_id:, created_at: Time.current)
      LineMusicTrack.create!(
        album: line_music_album.album,
        line_music_album:,
        track:,
        line_music_id:,
        name: 'Dedupe LINE MUSIC Track',
        disc_number: 1,
        track_number: 1
      ).tap { |record| overwrite_created_at(record, created_at) }
    end

    def create_ytmusic_album(album:, browse_id: nil, name: 'Dedupe YouTube Music Album', video_ids: [],
                             created_at: Time.current)
      YtmusicAlbum.create!(
        album:,
        browse_id: browse_id || "dedupe-yta-#{SecureRandom.hex(4)}",
        name:,
        payload: { 'tracks' => video_ids.map { |video_id| { 'video_id' => video_id } } }
      ).tap { |record| overwrite_created_at(record, created_at) }
    end

    def create_ytmusic_track(ytmusic_album:, track:, video_id:, created_at: Time.current)
      YtmusicTrack.create!(
        album: ytmusic_album.album,
        ytmusic_album:,
        track:,
        video_id:,
        playlist_id: "dedupe-ytpl-#{SecureRandom.hex(4)}",
        name: 'Dedupe YouTube Music Track',
        track_number: 1
      ).tap { |record| overwrite_created_at(record, created_at) }
    end

    def create_spotify_album
      album = create_album
      SpotifyAlbum.create!(
        album:,
        spotify_id: "dedupe-spa-#{SecureRandom.hex(4)}",
        album_type: 'album',
        name: 'Dedupe Spotify Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        total_tracks: 1,
        active: true,
        payload: {}
      )
    end

    def create_spotify_track(spotify_album:, track:, spotify_id:, created_at: Time.current)
      SpotifyTrack.create!(
        album: spotify_album.album,
        spotify_album:,
        track:,
        spotify_id:,
        name: 'Dedupe Spotify Track',
        label: Album::TOUHOU_MUSIC_LABEL,
        disc_number: 1,
        track_number: 1,
        duration_ms: 180_000,
        payload: {}
      ).tap { |record| overwrite_created_at(record, created_at) }
    end

    def create_spotify_track_with_album
      spotify_album = create_spotify_album
      create_spotify_track(
        spotify_album:,
        track: create_track(spotify_album.album),
        spotify_id: "dedupe-sp-#{SecureRandom.hex(4)}"
      )
    end

    def create_spotify_track_audio_feature(spotify_track:, tempo:, created_at: Time.current)
      SpotifyTrackAudioFeature.create!(
        track: spotify_track.track,
        spotify_track:,
        spotify_id: spotify_track.spotify_id,
        acousticness: 0.1,
        danceability: 0.2,
        duration_ms: 180_000,
        energy: 0.3,
        instrumentalness: 0.4,
        key: 1,
        liveness: 0.5,
        loudness: -5.0,
        mode: 1,
        speechiness: 0.6,
        tempo:,
        time_signature: 4,
        valence: 0.7
      ).tap { |record| overwrite_created_at(record, created_at) }
    end
  end
end
