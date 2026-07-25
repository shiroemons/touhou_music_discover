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

    # プールサイズは必ず RAILS_MAX_THREADS 以上にすること。
    # app/controllers/spotify/playlists_controller.rb が処理の進捗を Redis に
    # 継続的に書き込んでおり、ここでコネクションが枯渇すると各スレッドが
    # ConnectionPool::TimeoutError で待たされ、管理画面の進捗表示が停止してしまう。
    def pool
      @pool ||= ConnectionPool.new(
        size: ENV.fetch('REDIS_POOL_SIZE') { ENV.fetch('RAILS_MAX_THREADS', 5) }.to_i,
        timeout: ENV.fetch('REDIS_TIMEOUT', 5).to_f
      ) do
        Redis.new(
          url: ENV.fetch('REDIS_URL', 'redis://localhost:6379'),
          connect_timeout: 1, read_timeout: 1, write_timeout: 1,
          reconnect_attempts: [0.05, 0.1, 0.2]
        )
      end
    end
  end
end
