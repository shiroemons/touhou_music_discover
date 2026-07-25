# frozen_string_literal: true

require 'test_helper'

class SpotifyRetryTest < ActiveSupport::TestCase
  test '429 with a Retry-After header sleeps for that duration then succeeds' do
    error = too_many_requests(retry_after: 3)
    sleeps = []
    attempts = 0

    result = with_spotify_rate_limit_cache(ActiveSupport::Cache::MemoryStore.new) do
      SpotifyRetry.with_retry(source: 'test', sleeper: recording_sleeper(sleeps)) do |attempt, _exception|
        attempts += 1
        raise error if attempt.zero?

        :ok
      end
    end

    assert_equal :ok, result
    assert_equal [3], sleeps
    assert_equal 2, attempts
  end

  test '429 with Retry-After above max_retry_after re-raises immediately without sleeping' do
    error = too_many_requests(retry_after: 1_000)
    sleeps = []

    with_spotify_rate_limit_cache(ActiveSupport::Cache::MemoryStore.new) do
      assert_raises(RestClient::TooManyRequests) do
        SpotifyRetry.with_retry(source: 'test', max_retry_after: 900, sleeper: recording_sleeper(sleeps)) { raise error }
      end
    end

    assert_empty sleeps
  end

  test '429 without a Retry-After header falls back to DEFAULT_RETRY_AFTER' do
    error = too_many_requests(retry_after: nil)
    sleeps = []
    attempts = 0

    with_spotify_rate_limit_cache(ActiveSupport::Cache::MemoryStore.new) do
      SpotifyRetry.with_retry(source: 'test', sleeper: recording_sleeper(sleeps)) do |attempt, _exception|
        attempts += 1
        raise error if attempt.zero?

        :ok
      end
    end

    assert_equal [SpotifyRetry::DEFAULT_RETRY_AFTER], sleeps
  end

  test 'transient server errors back off exponentially within the jitter band' do
    sleeps = []

    assert_raises(RestClient::InternalServerError) do
      SpotifyRetry.with_retry(source: 'test', tries: 4, sleeper: recording_sleeper(sleeps)) do |_attempt, _exception|
        raise RestClient::InternalServerError
      end
    end

    expected_bases = [5, 10, 20]
    assert_equal expected_bases.size, sleeps.size

    sleeps.each_with_index do |delay, index|
      base = expected_bases[index]
      assert_operator delay, :>=, base
      assert_operator delay, :<=, base * (1 + SpotifyRetry::JITTER)
    end
  end

  test 're-raises the original exception once tries are exhausted' do
    error = RestClient::InternalServerError.new

    raised = assert_raises(RestClient::InternalServerError) do
      SpotifyRetry.with_retry(source: 'test', tries: 2, sleeper: recording_sleeper([])) { raise error }
    end

    assert_same error, raised
  end

  test 'records the Spotify rate limit status via SpotifyRateLimit on 429' do
    error = too_many_requests(retry_after: 5)
    attempts = 0

    with_spotify_rate_limit_cache(ActiveSupport::Cache::MemoryStore.new) do
      SpotifyRetry.with_retry(source: 'spec-source', sleeper: recording_sleeper([])) do |attempt, _exception|
        attempts += 1
        raise error if attempt.zero?

        :ok
      end

      status = SpotifyRateLimit.current
      assert_equal 5, status.retry_after
      assert_equal 'spec-source', status.source
    end
  end

  test 'yields attempt starting at 0 on the first try and the previous exception thereafter' do
    error = RestClient::InternalServerError.new
    observed = []

    SpotifyRetry.with_retry(source: 'test', sleeper: recording_sleeper([])) do |attempt, exception|
      observed << [attempt, exception]
      raise error if attempt.zero?

      :ok
    end

    assert_equal [0, nil], observed[0]
    assert_equal 1, observed[1][0]
    assert_same error, observed[1][1]
  end

  private

  # `sleeper:` に注入し、実際にスリープさせずに要求された待機秒数だけを記録する
  def recording_sleeper(sleeps)
    ->(seconds) { sleeps << seconds }
  end

  def too_many_requests(retry_after:)
    headers = retry_after.nil? ? {} : { retry_after: retry_after.to_s }
    response = Struct.new(:headers).new(headers)
    RestClient::TooManyRequests.new(response)
  end

  def with_spotify_rate_limit_cache(cache)
    SpotifyRateLimit.cache_store = cache
    yield
  ensure
    SpotifyRateLimit.cache_store = nil
  end
end
