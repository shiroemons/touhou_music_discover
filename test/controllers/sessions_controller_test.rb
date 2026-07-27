# frozen_string_literal: true

require 'test_helper'

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
    @auth = OmniAuth::AuthHash.new(
      provider: 'spotify',
      uid: 'test-user',
      info: { id: 'test-user', display_name: 'Test User', email: 'test@example.com',
              images: [{ 'url' => 'https://example.test/avatar.png' }] },
      credentials: { token: 'USER_TOKEN', refresh_token: 'REFRESH_TOKEN',
                     expires_at: 1.hour.from_now.to_i, expires: true }
    )
    OmniAuth.config.mock_auth[:spotify] = @auth
  end

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:spotify] = nil
    User.where(provider: 'spotify', uid: 'test-user').each do |u|
      RedisPool.with { |r| r.del(SpotifyApi::UserSession.redis_key(u.id), u.id) }
    end
  end

  test 'callback creates a user and stores the auth hash under a namespaced key with a TTL' do
    get '/auth/spotify/callback', env: { 'omniauth.auth' => @auth }

    assert_redirected_to root_path
    user = User.find_by!(provider: 'spotify', uid: 'test-user')

    key = SpotifyApi::UserSession.redis_key(user.id)
    stored = RedisPool.with { |r| r.get(key) }

    assert_not_nil stored
    assert_equal 'REFRESH_TOKEN', JSON.parse(stored).dig('credentials', 'refresh_token')

    ttl = RedisPool.with { |r| r.ttl(key) }

    assert_operator ttl, :>, 0
    assert_operator ttl, :<=, SpotifyApi::UserSession::TTL.to_i
  end

  test 'logout deletes the namespaced auth hash' do
    get '/auth/spotify/callback', env: { 'omniauth.auth' => @auth }
    user = User.find_by!(provider: 'spotify', uid: 'test-user')

    delete '/logout'

    assert_redirected_to root_path
    assert_nil(RedisPool.with { |r| r.get(SpotifyApi::UserSession.redis_key(user.id)) })
  end

  # Task 12 以前は user.id の生値をキーにしていたため、そのキーには TTL が無い
  # まま非破棄的トークンが残り続けうる。User は callback が作成するため、
  # 1回目のログインでユーザーを作ってから旧キーを仕込み、2回目のログインで
  # 削除されることを確認する。
  test 'callback deletes a legacy raw-user.id key left over from before the namespaced key existed' do
    get '/auth/spotify/callback', env: { 'omniauth.auth' => @auth }
    user = User.find_by!(provider: 'spotify', uid: 'test-user')
    RedisPool.with { |r| r.set(user.id, { 'legacy' => true }.to_json) }

    get '/auth/spotify/callback', env: { 'omniauth.auth' => @auth }

    assert_redirected_to root_path
    assert_nil(RedisPool.with { |r| r.get(user.id) })
    assert_not_nil(RedisPool.with { |r| r.get(SpotifyApi::UserSession.redis_key(user.id)) })
  end

  # 既存セッションがある状態で、旧キーが生き残っていてもログアウトで確実に消えることを固定する。
  test 'logout deletes a legacy raw-user.id key too' do
    get '/auth/spotify/callback', env: { 'omniauth.auth' => @auth }
    user = User.find_by!(provider: 'spotify', uid: 'test-user')
    RedisPool.with { |r| r.set(user.id, { 'legacy' => true }.to_json) }

    delete '/logout'

    assert_redirected_to root_path
    assert_nil(RedisPool.with { |r| r.get(user.id) })
  end
end
