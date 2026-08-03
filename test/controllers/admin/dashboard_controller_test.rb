# frozen_string_literal: true

require 'test_helper'

module Admin
  class DashboardControllerTest < ActionDispatch::IntegrationTest
    test 'shows admin dashboard without legacy admin links' do
      get admin_root_url

      assert_response :success
      assert_select 'h1', '管理画面'
      assert_select 'a[href=?]', '/avo', count: 0
      nav_group_labels = css_select('.admin-nav .admin-nav-group').map do |group|
        group.at_css('.admin-nav-heading').text.strip
      end

      assert_equal %w[マスタ 運用 カタログ 配信データ], nav_group_labels
      assert_select 'nav.admin-nav a.admin-nav-link[href=?]', admin_track_original_song_assignments_path,
                    text: '楽曲の原曲紐づけ'
      assert_select 'nav.admin-nav a.admin-nav-link[href=?]',
                    admin_resource_action_path('tracks', 'auto_assign_original_songs'),
                    text: '一致するアルバムから原曲を自動紐づけ'
      assert_select '.admin-theme-switcher[data-controller=?]', 'admin-theme'
      assert_select 'button[data-admin-theme-mode=?]', 'light', text: 'Light'
      assert_select 'button[data-admin-theme-mode=?]', 'dark', text: 'Dark'
      assert_select 'button[data-admin-theme-mode=?]', 'system', text: 'System'
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
      assert_select 'a[href=?]', admin_resource_action_path('spotify_tracks', 'fetch_missing_spotify_tracks'), text: '未取得だけ取得'
      assert_select 'a[href=?]', admin_resource_action_path('apple_music_tracks', 'fetch_missing_apple_music_tracks'), text: '未取得だけ取得'
      assert_select 'a[href=?]', admin_resource_action_path('line_music_tracks', 'fetch_missing_line_music_tracks'), text: '未取得だけ取得'
      assert_select 'a[href=?]', admin_resource_action_path('ytmusic_tracks', 'fetch_missing_ytmusic_tracks'), text: '未取得だけ取得'
      assert_select '.admin-missing-track-preview-header', text: /未取得楽曲/
      assert_select '.admin-priority-grid'
      assert_select '.admin-priority-grid h2', '作業キュー'
      assert_select '.admin-priority-grid h2', 'データ品質'
      assert_select 'h2', '作業キュー'
      assert_select 'h2', 'データ品質'
      assert_select 'h2', 'Spotifyプレイリスト同期'
      assert_select 'h2', 'リソース一覧'
      assert_select 'a[href=?]', admin_resources_path('albums'), text: 'アルバム'
      assert_select 'a[href=?]', admin_new_resource_path('albums'), text: '新規作成'
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

    private

    def with_spotify_rate_limit_cache(cache)
      SpotifyRateLimit.cache_store = cache
      yield
    ensure
      SpotifyRateLimit.cache_store = nil
    end
  end
end
