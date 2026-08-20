# frozen_string_literal: true

require 'test_helper'

module Admin
  class ActionsControllerTest < ActionDispatch::IntegrationTest
    include ActiveJob::TestHelper

    teardown do
      clear_enqueued_jobs
      clear_performed_jobs
    end

    test 'enqueues admin action job when running an action' do
      created_run = nil

      with_action_run_method(:create!, ->(**attrs) { created_run = attrs }) do
        assert_enqueued_with(job: Admin::ActionJob, queue: 'admin_actions') do
          post admin_resource_action_url('albums', 'change_touhou_flag')
        end
      end

      assert_response :redirect
      assert_match(%r{/admin/albums/actions/change_touhou_flag/runs/}, response.location)
      assert_equal 'albums', created_run.fetch(:resource_key)
      assert_equal 'change_touhou_flag', created_run.fetch(:action_key)
    end

    test 'previews the complete before and after matrix without changing original song links' do
      candidate = create_transfer_candidate
      create_obviously_different_album_pair

      assert_no_changes -> { candidate.fetch(:target_track).original_songs.reload.count } do
        get admin_resource_action_url('tracks', 'auto_assign_original_songs')
      end

      assert_response :success
      assert_select 'h1', text: '一致するアルバムから原曲を自動紐づけ'
      assert_select 'nav.admin-nav a.admin-nav-link.active[href=?]',
                    admin_resource_action_path('tracks', 'auto_assign_original_songs'),
                    text: '一致するアルバムから原曲を自動紐づけ'
      assert_select 'nav.admin-nav a.admin-nav-link.active[href=?]', admin_resources_path('tracks'), count: 0
      assert_select '.admin-transfer-metrics dd', text: '1'
      assert_select '.admin-transfer-matrix' do
        assert_select 'caption', /Transfer Preview Album/
        assert_select 'tbody tr', count: 1
        assert_select 'td strong', text: 'Transfer Preview Track', count: 1
        assert_select 'td strong', text: 'Transfer Preview Track English', count: 1
        assert_select '.admin-transfer-status.is-match', text: 'ISRC一致（表記違い）'
        assert_select '.admin-transfer-similarity meter[min="0"][max="100"]', count: 1
        assert_select '.admin-transfer-status.is-planned', text: '移行予定'
        assert_select '.admin-transfer-originals li', count: 1 do
          assert_select 'code', text: 'PREVIEW-ORIGINAL-SONG'
          assert_select 'span', text: 'Preview Original Song'
        end
      end
      assert_select 'button[type=submit]:not([disabled])', text: '1曲を自動紐づけ'
      assert_select '.admin-action-side-panel .alert-info', /既存リンクの上書きや削除は行いません/
      assert_select '.admin-action-checklist li', text: /外部API/, count: 0
      assert_select '.admin-transfer-exclusions', count: 0
      assert_select '*', text: 'Rejected Preview Album', count: 0
    end

    test 'does not enqueue the auto-link action when no safe candidates exist' do
      assert_no_enqueued_jobs do
        post admin_resource_action_url('tracks', 'auto_assign_original_songs')
      end

      assert_redirected_to admin_resource_action_path('tracks', 'auto_assign_original_songs')
      assert_equal I18n.t('admin.actions.auto_assign_original_songs.no_candidates'), flash[:alert]
    end

    test 'requires a replacement preview before allowing the LINE MUSIC album update' do
      album = Album.create!(jan_code: "admin-line-music-replacement-#{SecureRandom.hex(4)}")
      line_music_album = LineMusicAlbum.create!(
        album:,
        line_music_id: 'admin-old-line-album',
        name: 'Admin LINE MUSIC Album',
        total_tracks: 1,
        payload: {}
      )

      get admin_member_resource_action_url('line_music_albums', line_music_album, 'replace_line_music_album')

      assert_response :success
      assert_select 'form[action=?]', admin_member_resource_action_preview_path('line_music_albums', line_music_album, 'replace_line_music_album'), count: 1
      assert_select 'button[type=submit]', text: '照合結果を表示', count: 1
      assert_select 'input[name="fields[expected_old_line_music_id]"][value="admin-old-line-album"]', count: 1

      post admin_member_resource_action_preview_url('line_music_albums', line_music_album, 'replace_line_music_album'), params: {
        fields: {
          new_line_music_id: '',
          new_url: '',
          expected_old_line_music_id: 'admin-old-line-album'
        }
      }

      assert_response :success
      assert_select '.alert-error', text: /新しいLINE MUSICアルバムIDを入力してください/
      assert_select 'button[type=submit]', text: '照合結果を表示', count: 1
      assert_no_enqueued_jobs
    end

    test 'renders a successful LINE MUSIC replacement preview before enqueueing it' do
      album = Album.create!(jan_code: "admin-line-music-preview-#{SecureRandom.hex(4)}")
      line_music_album = LineMusicAlbum.create!(
        album:,
        line_music_id: 'admin-preview-old',
        name: 'Admin Preview Album',
        total_tracks: 1,
        payload: {}
      )
      api_album = Struct.new(:album_id, :album_title, :track_total_count).new('admin-preview-new', 'Admin Preview Album', 1)
      plan = LineMusicAlbumReplacement::Plan.new(
        line_music_album,
        api_album,
        [],
        [],
        'https://music.line.me/webapp/album/admin-preview-new',
        'admin-preview-old',
        { 'album' => {}, 'tracks' => [] },
        { 'album' => {}, 'tracks' => [] },
        { 'created' => 0, 'updated' => 1, 'removed' => 0, 'unchanged' => 0 },
        []
      )

      with_replacement_prepare(-> { plan }) do
        post admin_member_resource_action_preview_url('line_music_albums', line_music_album, 'replace_line_music_album'), params: {
          fields: {
            new_line_music_id: 'admin-preview-new',
            new_url: '',
            expected_old_line_music_id: 'admin-preview-old'
          }
        }
      end

      assert_response :success
      assert_select 'h3', text: '置換前後の照合結果'
      assert_select '.admin-action-status-pill', text: 'プレビュー（未更新）'
      assert_select 'button[type=submit]:not([disabled])', text: /置換を実行/
      assert_select 'form[action=?]', admin_member_resource_action_path('line_music_albums', line_music_album, 'replace_line_music_album'), count: 1
      assert_no_enqueued_jobs
    end

    test 'offers a response link for each detected LINE MUSIC replacement candidate' do
      album = Album.create!(jan_code: "admin-line-music-detection-#{SecureRandom.hex(4)}")
      line_music_album = LineMusicAlbum.create!(
        album:,
        line_music_id: 'admin-detection-old',
        name: 'Admin Detection Album',
        total_tracks: 1,
        payload: {}
      )
      candidate = Data.define(:album_id, :album_title, :release_date, :track_total_count).new(
        'admin-detection-new',
        'Admin Detection Album',
        Date.new(2026, 5, 4),
        1
      )
      plan = LineMusicAlbumReplacementDetector::Plan.new(line_music_album, [candidate], ['Admin Detection Album'], [])
      expected_path = admin_member_resource_action_path(
        'line_music_albums',
        line_music_album,
        'replace_line_music_album',
        new_line_music_id: candidate.album_id
      )

      with_detector_prepare(-> { plan }) do
        assert_no_difference -> { LineMusicAlbumReplacementCandidate.count } do
          get admin_member_resource_action_url('line_music_albums', line_music_album, 'detect_line_music_album_replacement')
        end
      end

      assert_response :success
      assert_select 'a[href=?]', expected_path, text: 'この候補で対応', count: 1
    end

    test 'prefills the selected replacement candidate in the replacement form' do
      album = Album.create!(jan_code: "admin-line-music-selected-#{SecureRandom.hex(4)}")
      line_music_album = LineMusicAlbum.create!(
        album:,
        line_music_id: 'admin-selected-old',
        name: 'Admin Selected Album',
        total_tracks: 1,
        payload: {}
      )
      LineMusicAlbumReplacementCandidate.create!(
        line_music_album:,
        line_music_id: 'admin-selected-new',
        name: 'Admin Selected Album',
        url: 'https://music.line.me/webapp/album/admin-selected-new',
        total_tracks: 1,
        payload: {}
      )

      get admin_member_resource_action_url(
        'line_music_albums',
        line_music_album,
        'replace_line_music_album',
        new_line_music_id: 'admin-selected-new'
      )

      assert_response :success
      assert_select 'input[name="fields[new_line_music_id]"][value="admin-selected-new"]', count: 1
      assert_select 'input[name="fields[new_url]"][value="https://music.line.me/webapp/album/admin-selected-new"]', count: 1
    end

    test 'shows a queued action without presenting it as running' do
      run_id = create_action_run

      get admin_resource_action_run_url('albums', 'change_touhou_flag', run_id)

      assert_response :success
      assert_select '#admin-action-progress[data-status="queued"][data-polling="true"]'
      assert_select '[data-admin-action-progress-target=?][role=?][hidden]', 'error', 'alert', count: 1
      assert_select 'button[data-admin-action-progress-target=?][data-action=?]',
                    'retry', 'admin-action-progress#retry', text: '進捗を再取得'
      assert_select '#admin-action-progress h2', text: I18n.t('admin.actions.progress.statuses.queued')
      assert_select '.admin-action-progress-percent', text: '—'
      assert_select '.admin-action-progress-meter.is-indeterminate', count: 0
      assert_select '.admin-action-progress-meta', text: /#{Regexp.escape(I18n.t('admin.actions.progress.queued'))}/
      assert_select '.admin-action-progress-result', count: 0
    ensure
      RedisPool.get.del("admin:action_runs:#{run_id}") if run_id
    end

    test 'shows an indeterminate running state after the background job starts' do
      run_id = create_action_run
      Admin::ActionRun.start!(run_id)

      get admin_resource_action_run_url('albums', 'change_touhou_flag', run_id)

      assert_response :success
      assert_select '#admin-action-progress[data-status="processing"][data-polling="true"]'
      assert_select '#admin-action-progress h2', text: I18n.t('admin.actions.progress.statuses.processing')
      assert_select '.admin-action-progress-percent', text: '0%'
      assert_select '.admin-action-progress-meter.is-indeterminate', count: 1
      assert_select '.admin-action-progress-meter[aria-valuenow]', count: 0
      assert_select '.admin-action-progress-result', count: 0
    ensure
      RedisPool.get.del("admin:action_runs:#{run_id}") if run_id
    end

    test 'shows a pre-progress failure once without a zero progress count' do
      run_id = create_action_run
      error_message = 'uninitialized constant Admin::Example'
      Admin::ActionRun.update!(
        run_id,
        status: 'error',
        current: 0,
        total: 0,
        message: error_message,
        result_message: error_message,
        result_status: 'error'
      )

      get admin_resource_action_run_url('albums', 'change_touhou_flag', run_id)

      assert_response :success
      assert_select '#admin-action-progress[data-status="error"][data-polling="false"]'
      assert_select '.admin-action-progress-percent', text: '—'
      assert_select '.admin-action-progress-meter[aria-valuenow]', count: 0
      assert_select '.admin-action-progress-meta', text: /進捗の記録を開始する前に失敗しました。/
      assert_select '.admin-action-progress-meta', text: %r{0 / 0}, count: 0
      assert_select '.admin-action-progress-result-content p', text: error_message, count: 1
      assert_equal 1, response.body.scan(error_message).size
    ensure
      RedisPool.get.del("admin:action_runs:#{run_id}") if run_id
    end

    test 'progress response explicitly reports whether polling should continue' do
      run_id = create_action_run

      get admin_resource_action_run_progress_url('albums', 'change_touhou_flag', run_id),
          headers: { 'Accept' => Mime[:turbo_stream].to_s }

      assert_response :success
      assert_equal 'true', response.headers['X-Admin-Action-Polling']

      Admin::ActionRun.update!(run_id, status: 'completed')

      get admin_resource_action_run_progress_url('albums', 'change_touhou_flag', run_id),
          headers: { 'Accept' => Mime[:turbo_stream].to_s }

      assert_response :success
      assert_equal 'false', response.headers['X-Admin-Action-Polling']
    ensure
      RedisPool.get.del("admin:action_runs:#{run_id}") if run_id
    end

    private

    def create_action_run
      run_id = SecureRandom.uuid
      Admin::ActionRun.create!(
        run_id:,
        resource_key: 'albums',
        action_key: 'change_touhou_flag',
        action_label: '東方フラグを変更',
        redirect_path: '/admin/albums'
      )
      run_id
    end

    def with_action_run_method(method_name, replacement)
      original = Admin::ActionRun.method(method_name)
      Admin::ActionRun.define_singleton_method(method_name, replacement)
      yield
    ensure
      Admin::ActionRun.define_singleton_method(method_name, original)
    end

    def with_replacement_prepare(replacement)
      original_method = LineMusicAlbumReplacement.instance_method(:prepare)
      LineMusicAlbumReplacement.define_method(:prepare, &replacement)
      yield
    ensure
      LineMusicAlbumReplacement.define_method(:prepare, original_method)
    end

    def with_detector_prepare(replacement)
      original_method = LineMusicAlbumReplacementDetector.instance_method(:prepare)
      LineMusicAlbumReplacementDetector.define_method(:prepare, &replacement)
      yield
    ensure
      LineMusicAlbumReplacementDetector.define_method(:prepare, original_method)
    end

    def create_transfer_candidate
      circle = Circle.create!(name: 'Transfer Preview Circle')
      source_album = Album.create!(jan_code: '4990000000001')
      target_album = Album.create!(jan_code: '4990000000002')
      CirclesAlbum.create!(album: source_album, circle:)
      CirclesAlbum.create!(album: target_album, circle:)
      source_track = Track.create!(album: source_album, isrc: 'JPPREVIEW001')
      target_track = Track.create!(album: target_album, isrc: 'JPPREVIEW001')
      original = Original.create!(
        code: 'PREVIEW-ORIGINAL',
        title: 'Preview Original',
        short_title: 'Preview',
        original_type: 'other',
        series_order: 999
      )
      original_song = OriginalSong.create!(
        code: 'PREVIEW-ORIGINAL-SONG',
        original:,
        title: 'Preview Original Song',
        composer: 'ZUN',
        track_number: 1
      )
      TracksOriginalSong.create!(track: source_track, original_song:)
      source_catalog = SpotifyAlbum.create!(
        album: source_album,
        spotify_id: 'preview-source-album',
        album_type: 'album',
        name: 'Transfer Preview Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        total_tracks: 1,
        active: true,
        payload: {}
      )
      target_catalog = SpotifyAlbum.create!(
        album: target_album,
        spotify_id: 'preview-target-album',
        album_type: 'album',
        name: 'Transfer Preview Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        total_tracks: 1,
        active: true,
        payload: {}
      )
      [source_catalog, target_catalog]
        .zip([source_track, target_track], ['Transfer Preview Track', 'Transfer Preview Track English'])
        .each do |catalog, track, name|
          SpotifyTrack.create!(
            album: catalog.album,
            track:,
            spotify_album: catalog,
            spotify_id: "preview-track-#{catalog.id}",
            name:,
            label: Album::TOUHOU_MUSIC_LABEL,
            disc_number: 1,
            track_number: 1,
            payload: {}
          )
        end

      { target_track: }
    end

    def create_obviously_different_album_pair
      circle = Circle.create!(name: 'Rejected Preview Circle')
      source_album = Album.create!(jan_code: '4990000000011')
      target_album = Album.create!(jan_code: '4990000000012')
      CirclesAlbum.create!(album: source_album, circle:)
      CirclesAlbum.create!(album: target_album, circle:)
      source_tracks = [
        Track.create!(album: source_album, isrc: 'JPREJECT001'),
        Track.create!(album: source_album, isrc: 'JPREJECT002')
      ]
      target_track = Track.create!(album: target_album, isrc: 'JPREJECT101')
      original = Original.create!(
        code: 'REJECTED-PREVIEW-ORIGINAL',
        title: 'Rejected Preview Original',
        short_title: 'Rejected Preview',
        original_type: 'other',
        series_order: 999
      )
      song = OriginalSong.create!(
        code: 'REJECTED-PREVIEW-SONG',
        original:,
        title: 'Rejected Preview Song',
        composer: 'ZUN',
        track_number: 1
      )
      TracksOriginalSong.create!(track: source_tracks.first, original_song: song)
      source_catalog = SpotifyAlbum.create!(
        album: source_album,
        spotify_id: 'rejected-preview-source-album',
        album_type: 'album',
        name: 'Rejected Preview Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        total_tracks: 2,
        active: true,
        payload: {}
      )
      target_catalog = SpotifyAlbum.create!(
        album: target_album,
        spotify_id: 'rejected-preview-target-album',
        album_type: 'album',
        name: 'Rejected Preview Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        total_tracks: 1,
        active: true,
        payload: {}
      )
      source_tracks.each_with_index do |track, index|
        create_preview_spotify_track(source_catalog, track, "Rejected Source #{index + 1}", index + 1)
      end
      create_preview_spotify_track(target_catalog, target_track, 'Rejected Source 1', 1)
    end

    def create_preview_spotify_track(catalog, track, name, track_number)
      SpotifyTrack.create!(
        album: catalog.album,
        track:,
        spotify_album: catalog,
        spotify_id: "preview-track-#{SecureRandom.hex(5)}",
        name:,
        label: Album::TOUHOU_MUSIC_LABEL,
        disc_number: 1,
        track_number:,
        payload: {}
      )
    end
  end
end
