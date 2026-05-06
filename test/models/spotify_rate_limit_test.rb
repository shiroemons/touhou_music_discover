# frozen_string_literal: true

require 'test_helper'

class SpotifyRateLimitTest < ActiveSupport::TestCase
  test 'records and returns current Spotify retry after status' do
    cache = ActiveSupport::Cache::MemoryStore.new
    observed_at = Time.zone.parse('2026-05-06 12:00:00')

    with_spotify_rate_limit_cache(cache) do
      status = SpotifyRateLimit.record!(retry_after: 3267, source: 'test', observed_at:)

      assert_equal 3267, status.retry_after
      assert_equal observed_at + 3267.seconds, status.expires_at
      assert_equal 'test', status.source
      assert_equal '54分27秒', status.retry_after_duration

      current = SpotifyRateLimit.current(now: observed_at + 10.seconds)
      assert_equal 3267, current.retry_after
      assert_equal 3257, current.remaining_seconds(now: observed_at + 10.seconds)

      assert_nil SpotifyRateLimit.current(now: observed_at + 3268.seconds)
    end
  end

  test 'extracts retry after seconds from RestClient style headers' do
    error = Struct.new(:http_headers).new({ retry_after: '3267' })

    assert_equal 3267, SpotifyRateLimit.retry_after_seconds(error)
  end

  test 'formats durations for display' do
    assert_equal '54分27秒', SpotifyRateLimit.format_duration(3267)
    assert_equal '1時間1分1秒', SpotifyRateLimit.format_duration(3661)
    assert_equal '45秒', SpotifyRateLimit.format_duration(45)
  end

  test 'returns display times in Japan time' do
    status = SpotifyRateLimit::Status.new(
      retry_after: 3267,
      observed_at: Time.utc(2026, 5, 6, 3, 0, 0),
      expires_at: Time.utc(2026, 5, 6, 3, 54, 27),
      source: 'test'
    )

    assert_equal 'Asia/Tokyo', status.observed_at_jst.time_zone.name
    assert_equal Time.find_zone!('Asia/Tokyo').parse('2026-05-06 12:00:00'), status.observed_at_jst
    assert_equal Time.find_zone!('Asia/Tokyo').parse('2026-05-06 12:54:27'), status.expires_at_jst
  end

  private

  def with_spotify_rate_limit_cache(cache)
    SpotifyRateLimit.cache_store = cache
    yield
  ensure
    SpotifyRateLimit.cache_store = nil
  end
end
