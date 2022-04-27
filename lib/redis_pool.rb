# frozen_string_literal: true

require 'connection_pool'

class RedisPool
  class Wrapper < ConnectionPool::Wrapper
    def initialize(pool)
      @pool = pool
    end
  end

  class << self
    # Redis へのコネクションを取得する
    def with(&)
      pool.with(&)
    end

    # Redis へのコネクションを取得する (redis.gem との互換性維持用)
    def get
      Wrapper.new(pool)
    end

    private

    def pool
      @pool ||= ConnectionPool.new(
        size: ENV.fetch('RAILS_MAX_THREADS', 2).to_i,
        timeout: ENV.fetch('REDIS_TIMEOUT', 1).to_i
      ) { Redis.new(url: ENV.fetch('REDIS_URL', nil)) }
    end
  end
end
