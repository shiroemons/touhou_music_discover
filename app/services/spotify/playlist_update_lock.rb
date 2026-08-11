# frozen_string_literal: true

require 'securerandom'

module Spotify
  # 一括更新と個別更新が同じユーザーのプレイリストを同時に書き換えないための Redis ロック。
  #
  # Web プロセスが複数台になっても共有できるよう、プロセス内 Mutex ではなく Redis を使う。
  # TTL はワーカー異常終了時の復旧用で、正常終了時は所有トークンを確認して解放する。
  class PlaylistUpdateLock
    TTL = 6.hours.to_i
    KEY_PREFIX = 'spotify:playlist_update:lock:'
    RELEASE_SCRIPT = <<~LUA
      if redis.call('get', KEYS[1]) == ARGV[1] then
        return redis.call('del', KEYS[1])
      end
      return 0
    LUA

    class BusyError < StandardError; end

    class << self
      def with(user_id, &)
        new(user_id).with(&)
      end

      def key(user_id)
        "#{KEY_PREFIX}#{user_id}"
      end
    end

    def initialize(user_id, ttl: TTL)
      @key = self.class.key(user_id)
      @ttl = ttl
      @token = SecureRandom.uuid
      @acquired = false
    end

    def with
      acquire!
      yield
    ensure
      release!
    end

    # Background processing needs to keep the lock after the HTTP request has
    # returned. Exposing the lifecycle explicitly also makes the ownership
    # boundary visible at the call site.
    def acquire!
      acquire
      self
    end

    def release!
      return unless @acquired

      begin
        release
      ensure
        @acquired = false
      end
    end

    private

    attr_reader :key, :ttl, :token

    def acquire
      acquired = RedisPool.with { |redis| redis.set(key, token, nx: true, ex: ttl) }
      raise BusyError, 'Spotifyプレイリスト更新がすでに実行中です' unless acquired

      @acquired = true
    end

    def release
      RedisPool.with { |redis| redis.eval(RELEASE_SCRIPT, keys: [key], argv: [token]) }
    end
  end
end
