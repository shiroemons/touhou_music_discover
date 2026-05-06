# frozen_string_literal: true

require 'test_helper'

module Admin
  class DashboardControllerTest < ActionDispatch::IntegrationTest
    test 'shows admin dashboard without depending on avo routes' do
      get admin_root_url

      assert_response :success
      assert_select 'h1', '管理画面'
      assert_select 'a[href=?]', '/avo', count: 0
      assert_select '.admin-stat-card', minimum: 4
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
