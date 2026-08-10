# frozen_string_literal: true

require 'test_helper'

module Admin
  class DashboardControllerTest < ActionDispatch::IntegrationTest
    test 'shows admin dashboard without legacy admin links' do
      get admin_root_url

      assert_response :success
      assert_select 'h1', '管理画面'
      assert_select 'link[rel=?][type=?][href=?]', 'icon', 'image/svg+xml', '/icon.svg'
      assert_select 'a.admin-skip-link[href=?]', '#admin-main-content', text: '本文へ移動'
      assert_select 'main#admin-main-content[tabindex=?]', '-1'
      assert_select 'a[href=?]', '/avo', count: 0
      assert_select 'nav.admin-nav[aria-label=?]', '管理画面ナビゲーション'
      assert_select 'button.admin-mobile-nav-trigger[aria-controls=?][aria-expanded=?]', 'admin-sidebar', 'false'
      assert_select 'aside#admin-sidebar[data-admin-mobile-nav-target=?][aria-hidden=?]', 'drawer', 'true'
      assert_select 'button.admin-mobile-nav-close[aria-label=?]', 'メニューを閉じる'
      assert_select 'button.admin-mobile-nav-backdrop[aria-label=?][hidden]', 'メニューを閉じる'
      assert_select 'nav.admin-nav a.admin-nav-link[aria-current=?]', 'page', count: 1
      nav_group_labels = css_select('.admin-nav .admin-nav-group').map do |group|
        group.at_css('.admin-nav-heading').text.strip
      end

      assert_equal %w[マスタ 運用 カタログ 配信データ], nav_group_labels
      assert_select 'nav.admin-nav a.admin-nav-link[href=?]', admin_track_original_song_assignments_path,
                    text: '楽曲の原曲紐づけ'
      assert_select 'nav.admin-nav a.admin-nav-link[href=?]',
                    admin_resource_action_path('tracks', 'auto_assign_original_songs'),
                    text: '一致するアルバムから原曲を自動紐づけ'
      assert_select 'details.admin-theme-switcher[data-controller=?] summary.admin-theme-trigger[aria-label=?]', 'admin-theme', '表示設定'
      assert_select 'button[data-admin-theme-mode=?][aria-label=?]', 'light', '明るいテーマ'
      assert_select 'button[data-admin-theme-mode=?][aria-label=?]', 'dark', '暗いテーマ'
      assert_select 'button[data-admin-theme-mode=?][aria-label=?]', 'system', 'システム設定に合わせる'
      assert_select '.admin-toast-container[data-controller=?][aria-label=?]', 'admin-toast', '通知'
      assert_select '.admin-toast-item', count: 0
      assert_select '.admin-stat-card', minimum: 4
      assert_select 'h2', 'カタログ整備状況'
      assert_select '.admin-catalog-metric-card', text: /サークル未設定アルバム/
      assert_select '.admin-catalog-metric-card', text: /原曲未紐付け楽曲/
      assert_select '.admin-catalog-metric-card', text: /オリジナル・その他/
      assert_select '.admin-catalog-metric-card', text: /東方アレンジ/
      assert_select '.admin-catalog-chart h3', '楽曲分類'
      assert_select '.admin-catalog-chart h3', 'サークル紐づけ'
      assert_select 'h2', '配信カバレッジ'
      assert_select '.admin-coverage-action', text: /アルバム未取得/
      assert_select '.admin-coverage-action', text: /楽曲未取得/
      assert_select '.admin-coverage-action', text: /楽曲不足アルバム/
      assert_select 'a[href=?]', admin_resource_action_path('spotify_tracks', 'fetch_missing_spotify_tracks'), count: 0
      assert_select 'a[href=?]', admin_resource_action_path('apple_music_tracks', 'fetch_missing_apple_music_tracks'), count: 0
      assert_select 'a[href=?]', admin_resource_action_path('line_music_tracks', 'fetch_missing_line_music_tracks'), count: 0
      assert_select 'a[href=?]', admin_resource_action_path('ytmusic_tracks', 'fetch_missing_ytmusic_tracks'), count: 0
      assert_select '.admin-coverage-fetch-actions [role=?]', 'status', count: 4, text: '取得対象なし'
      assert_select '.admin-missing-track-preview-header', text: /未取得楽曲/
      assert_select '.admin-priority-grid'
      assert_select '.admin-priority-grid h2', '作業キュー'
      assert_select '.admin-priority-grid h2', 'データ品質'
      assert_select '.admin-dashboard-disclosure summary', minimum: 4
      assert_select 'h2', '作業キュー'
      assert_select 'h2', 'データ品質'
      assert_select 'h2', 'Spotifyプレイリスト同期'
      assert_select 'h2', 'リソース一覧'
      assert_select 'a[href=?]', admin_resources_path('albums'), text: 'アルバム'
      assert_select 'a[href=?]', admin_new_resource_path('albums'), text: '新規作成'
    end

    test 'keeps the missing-track fetch action when it has targets' do
      album = Album.create!(jan_code: '4980000000301')
      Track.create!(album:, jan_code: album.jan_code, isrc: 'JPABC2600301')
      SpotifyAlbum.create!(
        album:,
        active: true,
        spotify_id: 'dashboard-targeted-fetch-album',
        album_type: 'album',
        name: 'Dashboard Targeted Fetch Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        total_tracks: 1
      )

      get admin_root_url

      assert_response :success
      assert_select '.admin-coverage-card.is-spotify' do
        assert_select 'a[href=?]', admin_resource_action_path('spotify_tracks', 'fetch_missing_spotify_tracks'),
                      text: '1アルバムの楽曲を取得'
        assert_select '[role=?]', 'status', count: 0
        assert_select 'a[href=?]', admin_resources_path('tracks', filters: { missing_streaming_track: 'spotify' }),
                      text: '未取得を確認'
      end
    end

    test 'does not offer a missing-track fetch action when only the track is missing' do
      album = Album.create!(jan_code: '4980000000302')
      Track.create!(album:, jan_code: album.jan_code, isrc: 'JPABC2600302')

      get admin_root_url

      assert_response :success
      assert_select '.admin-coverage-card.is-spotify' do
        assert_select 'a[href=?]', admin_resource_action_path('spotify_tracks', 'fetch_missing_spotify_tracks'), count: 0
        assert_select '[role=?]', 'status', text: '取得対象なし'
        assert_select 'a[href=?]', admin_resources_path('tracks', filters: { missing_streaming_track: 'spotify' }),
                      text: '未取得を確認'
      end
    end

    test 'shows Spotify rate limit countdown when Retry-After is recorded' do
      cache = ActiveSupport::Cache::MemoryStore.new
      observed_at = Time.current.change(usec: 0)
      expires_at = observed_at + 3267.seconds

      with_spotify_rate_limit_cache(cache) do
        SpotifyRateLimit.record!(retry_after: 3267, source: 'test', observed_at:)

        travel_to observed_at + 10.seconds do
          get admin_root_url
        end

        assert_response :success
        assert_select '.admin-rate-limit-banner[data-controller=?]', 'countdown'
        assert_select '.admin-rate-limit-banner[data-countdown-expires-at-value=?]', expires_at.to_i.to_s
        assert_select '.admin-rate-limit-kicker', 'Spotify API 429'
        assert_select '.admin-rate-limit-body strong', 'Spotify APIのレート制限中'
        assert_select '[data-countdown-target=?]', 'seconds', '54分17秒'
        assert_select '.admin-rate-limit-schedule', /再開予定: .+（日本時間）/
        assert_select '.admin-rate-limit-meta', /検出: .+（日本時間）/
      end
    end

    test 'links missing Spotify audio features to the retrieval action' do
      album = Album.create!(jan_code: '4980000000201')
      track = Track.create!(album:, jan_code: album.jan_code, isrc: 'JPABC2600201')
      spotify_album = SpotifyAlbum.create!(
        album:,
        spotify_id: 'dashboard-audio-feature-album',
        album_type: 'album',
        name: 'Dashboard Audio Feature Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        total_tracks: 1
      )
      SpotifyTrack.create!(
        album:,
        track:,
        spotify_album:,
        spotify_id: 'dashboard-audio-feature-track',
        name: 'Dashboard Audio Feature Track',
        label: Album::TOUHOU_MUSIC_LABEL
      )

      get admin_root_url

      assert_response :success
      assert_select 'a[href=?]', admin_resource_action_path('spotify_track_audio_features', 'fetch_missing_spotify_audio_features'),
                    text: /Spotify音響特徴未取得/
    end

    private

    def with_spotify_rate_limit_cache(cache)
      SpotifyRateLimit.cache_store = cache
      yield
    ensure
      SpotifyRateLimit.cache_store = nil
    end
  end
end
