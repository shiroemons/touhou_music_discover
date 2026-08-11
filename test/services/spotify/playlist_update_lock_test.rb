# frozen_string_literal: true

require 'test_helper'

module Spotify
  class PlaylistUpdateLockTest < ActiveSupport::TestCase
    test 'allows only one owner and releases only its own token' do
      user_id = "lock-test-#{SecureRandom.uuid}"
      first = PlaylistUpdateLock.new(user_id, ttl: 60)
      second = PlaylistUpdateLock.new(user_id, ttl: 60)

      first.acquire!
      assert_raises(PlaylistUpdateLock::BusyError) { second.acquire! }

      first.release!
      second.acquire!

      assert(RedisPool.with { |redis| redis.get(PlaylistUpdateLock.key(user_id)).present? })
    ensure
      first&.release!
      second&.release!
    end
  end
end
