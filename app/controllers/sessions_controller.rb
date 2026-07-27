# frozen_string_literal: true

class SessionsController < ApplicationController
  # ログアウト処理ではCSRF検証をスキップ（セキュリティ上問題ない）
  skip_before_action :verify_authenticity_token, only: [:destroy]
  def create
    user = User.find_or_create_from_auth_hash(auth_hash)
    RedisPool.with do |redis|
      redis.set(SpotifyApi::UserSession.redis_key(user.id), auth_hash.to_json,
                ex: SpotifyApi::UserSession::TTL.to_i)
      # Task 12 以前は user.id をそのままキーにしていた。旧キーは TTL が無く、
      # ログアウト時の削除対象にもならないため、ログインのタイミングで確実に消す。
      redis.del(user.id)
    end

    session[:user_id] = user.id
    redirect_to root_path
  end

  def destroy
    if session[:user_id]
      RedisPool.with do |redis|
        redis.del(SpotifyApi::UserSession.redis_key(session[:user_id]))
        redis.del(session[:user_id])
      end
    end
    reset_session
    redirect_to root_path
  end

  protected

  def auth_hash
    request.env['omniauth.auth']
  end
end
