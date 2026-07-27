# frozen_string_literal: true

require 'test_helper'

module SpotifyApi
  class UserSessionTest < ActiveSupport::TestCase
    JSON_HEADERS = { 'Content-Type' => 'application/json' }.freeze

    # RedisPool をスタブするための最小限の Redis 互換オブジェクト。
    # 実 Redis には一切依存しない。
    class FakeRedis
      attr_reader :store, :ttls

      def initialize(store = {})
        @store = store
        @ttls = {}
      end

      def get(key)
        @store[key]
      end

      # ex: は実 Redis クライアント（redis gem）の SET オプション名に合わせている。
      def set(key, value, ex: nil) # rubocop:disable Naming/MethodParameterName
        @store[key] = value
        @ttls[key] = ex
      end
    end

    setup do
      @stubs = Faraday::Adapter::Test::Stubs.new
      @config = Config.new
      @config.client_id = 'CLIENT_ID'
      @config.client_secret = 'CLIENT_SECRET'
      @config.token_connection = Faraday.new do |conn|
        conn.response :json, content_type: /\bjson$/
        conn.adapter :test, @stubs
      end
    end

    test 'access_token returns the existing token while it is still within the refresh margin' do
      calls = stub_refresh('NEW')
      session = build_session(token: 'OLD', expires_in: 3600)

      assert_equal 'OLD', session.access_token

      travel_to 3600.seconds.from_now - UserSession::REFRESH_MARGIN - 1.minute do
        assert_equal 'OLD', session.access_token
      end

      assert_equal 0, calls.value
    end

    test 'access_token refreshes once the refresh margin is reached' do
      calls = stub_refresh('NEW')
      session = build_session(token: 'OLD', expires_in: 3600)

      travel_to 3600.seconds.from_now - UserSession::REFRESH_MARGIN + 1.minute do
        assert_equal 'NEW', session.access_token
      end

      assert_equal 1, calls.value
    end

    test 'refresh! reflects the refreshed token and expiry' do
      stub_refresh('NEW', expires_in: 1800)
      session = build_session(token: 'OLD', expires_in: 3600)

      session.refresh!

      assert_equal 'NEW', session.access_token
      assert_in_delta (Time.current + 1800).to_i, session.expires_at.to_i, 1
    end

    test 'keeps the existing refresh_token when the refresh response does not include one' do
      stub_refresh('NEW', include_refresh_token: false)
      session = build_session(token: 'OLD', expires_in: -10, refresh_token: 'ORIGINAL_REFRESH')

      session.access_token

      assert_equal 'ORIGINAL_REFRESH', session.refresh_token
    end

    test 'rotates the refresh_token when the refresh response includes a new one' do
      stub_refresh('NEW', include_refresh_token: true)
      session = build_session(token: 'OLD', expires_in: -10, refresh_token: 'ORIGINAL_REFRESH')

      session.access_token

      assert_equal 'ROTATED_REFRESH', session.refresh_token
    end

    test 'writes the refreshed auth_hash back to Redis when user_id is known' do
      stub_refresh('NEW', expires_in: 1800)
      fake_redis = FakeRedis.new
      session = build_session(token: 'OLD', expires_in: -10, user_id: 'user-1')

      stub_redis_pool(fake_redis) do
        session.access_token
      end

      saved = JSON.parse(fake_redis.get(UserSession.redis_key('user-1')))

      assert_equal 'NEW', saved['credentials']['token']
      assert_equal UserSession::TTL.to_i, fake_redis.ttls[UserSession.redis_key('user-1')]
    end

    test 'does not write back to Redis when user_id is unknown' do
      stub_refresh('NEW', expires_in: 1800)
      session = build_session(token: 'OLD', expires_in: -10, user_id: nil)

      stub_redis_pool(raises: 'RedisPool.with must not be called without a user_id') do
        assert_equal 'NEW', session.access_token
      end
    end

    test 'does not raise when writing back to Redis fails; the refreshed token is still returned' do
      stub_refresh('NEW', expires_in: 1800)
      session = build_session(token: 'OLD', expires_in: -10, user_id: 'user-1')

      stub_redis_pool(raises: IOError.new('boom')) do
        assert_equal 'NEW', session.access_token
      end
    end

    test 'raises AuthenticationError when the token is expired and there is no refresh_token' do
      session = build_session(token: 'OLD', expires_in: -10, refresh_token: nil)

      assert_raises(AuthenticationError) { session.access_token }
    end

    test 'raises AuthenticationError when the refresh endpoint responds with a non-200 status' do
      @stubs.post('/api/token') { [400, JSON_HEADERS, { error: 'invalid_grant' }.to_json] }
      session = build_session(token: 'OLD', expires_in: -10)

      error = assert_raises(AuthenticationError) { session.access_token }

      assert_equal 400, error.status
      assert_not_nil error.response
    end

    test 'find loads the auth_hash from Redis' do
      auth_json = build_auth_hash(token: 'STORED', expires_in: 3600).to_json
      fake_redis = FakeRedis.new(UserSession.redis_key('user-1') => auth_json)

      session = stub_redis_pool(fake_redis) { UserSession.find('user-1', config: @config) }

      assert_equal 'STORED', session.access_token
      assert_equal 'spotify-uid', session.spotify_user_id
    end

    # 旧 rspotify 経由の実装 (RSpotify::User) は、該当ユーザーの認証情報が見つからないと
    # 「最初に登録されたユーザーのトークン」にフォールバックし、別人のアカウントを
    # 操作してしまう事故につながる仕様だった。SpotifyApi::UserSession は
    # この挙動を絶対に引き継がず、見つからなければ nil を返すだけであることを確認する。
    test 'find returns nil instead of falling back to another user\'s credentials' do
      auth_json = build_auth_hash(token: 'STORED', expires_in: 3600).to_json
      fake_redis = FakeRedis.new(UserSession.redis_key('user-1') => auth_json)

      session = stub_redis_pool(fake_redis) { UserSession.find('user-2', config: @config) }

      assert_nil session
    end

    test 'redis_key namespaces the auth hash' do
      assert_equal 'spotify:auth:abc-123', SpotifyApi::UserSession.redis_key('abc-123')
    end

    test 'find reads from the namespaced key' do
      user_id = SecureRandom.uuid
      hash = { 'uid' => 'test-user',
               'credentials' => { 'token' => 'T', 'refresh_token' => 'R',
                                  'expires_at' => 1.hour.from_now.to_i } }
      RedisPool.with { |r| r.set(SpotifyApi::UserSession.redis_key(user_id), hash.to_json) }

      session = SpotifyApi::UserSession.find(user_id)

      assert_not_nil session
      assert_equal 'test-user', session.spotify_user_id
    ensure
      RedisPool.with { |r| r.del(SpotifyApi::UserSession.redis_key(user_id)) }
    end

    # FakeRedis は「persist! が ex: を渡す意図」しか検証できない。実 Redis 上で
    # SET を ex: 無しで発行すると既存の TTL が消える仕様があるため、実際にリフレッシュを
    # 発生させて TTL が維持されることまで確認する。
    test 'the TTL is renewed rather than dropped when the token is refreshed' do
      user_id = SecureRandom.uuid
      key = SpotifyApi::UserSession.redis_key(user_id)
      hash = { 'uid' => 'test-user',
               'credentials' => { 'token' => 'OLD', 'refresh_token' => 'R',
                                  'expires_at' => 1.hour.ago.to_i } }
      RedisPool.with { |r| r.set(key, hash.to_json, ex: SpotifyApi::UserSession::TTL.to_i) }
      stub_spotify_token_refresh

      SpotifyApi::UserSession.find(user_id).access_token

      stored = JSON.parse(RedisPool.with { |r| r.get(key) })

      assert_equal 'NEW_ACCESS_TOKEN', stored.dig('credentials', 'token')

      ttl = RedisPool.with { |r| r.ttl(key) }

      assert_operator ttl, :>, 0
      assert_operator ttl, :<=, SpotifyApi::UserSession::TTL.to_i
    ensure
      RedisPool.with { |r| r.del(key) }
    end

    test 'access_token refreshes only once when called from multiple threads' do
      calls = stub_refresh('NEW', delay: 0.05)
      session = build_session(token: 'OLD', expires_in: -10)

      tokens = Array.new(5) { Thread.new { session.access_token } }.map(&:value)

      assert_equal ['NEW'] * 5, tokens
      assert_equal 1, calls.value
    end

    private

    # RedisPool.with を一時的に差し替える。minitest 6 は Object#stub（旧 minitest/mock）を
    # 同梱しなくなったため、ここでは特異メソッドの差し替え・復元を自前で行う。
    # fake_redis を渡すとそれを yield し、raises を渡すと RedisPool.with 呼び出し自体を
    # 例外にする（「呼ばれないこと」「呼び出しが失敗しても処理が継続すること」の検証用）。
    def stub_redis_pool(fake_redis = nil, raises: nil)
      original = RedisPool.singleton_class.instance_method(:with)
      RedisPool.define_singleton_method(:with) do |&blk|
        raise raises if raises

        blk.call(fake_redis)
      end

      yield
    ensure
      RedisPool.define_singleton_method(:with, original)
    end

    def build_session(token:, expires_in:, refresh_token: 'REFRESH', user_id: nil)
      UserSession.new(build_auth_hash(token:, expires_in:, refresh_token:), user_id:, config: @config)
    end

    def build_auth_hash(token:, expires_in:, refresh_token: 'REFRESH')
      {
        'provider' => 'spotify',
        'uid' => 'spotify-uid',
        'info' => { 'id' => 'spotify-uid', 'display_name' => 'Reimu' },
        'credentials' => {
          'token' => token,
          'refresh_token' => refresh_token,
          'expires_at' => Time.current.to_i + expires_in,
          'expires' => true
        }
      }
    end

    # トークンエンドポイントをスタブし、呼び出し回数を数えるカウンタを返す。
    def stub_refresh(token, expires_in: 3600, include_refresh_token: true, delay: nil)
      calls = Concurrent::AtomicFixnum.new(0)

      @stubs.post('/api/token') do
        calls.increment
        sleep delay if delay
        body = { access_token: token, expires_in: expires_in }
        body[:refresh_token] = 'ROTATED_REFRESH' if include_refresh_token
        [200, JSON_HEADERS, body.to_json]
      end

      calls
    end
  end
end
