# frozen_string_literal: true

class SessionsController < ApplicationController
  # ログアウト処理ではCSRF検証をスキップ（セキュリティ上問題ない）
  skip_before_action :verify_authenticity_token, only: [:destroy]
  def create
    user = User.find_or_create_from_auth_hash(auth_hash)
    RedisPool.with do |redis|
      redis.set(user.id, auth_hash.to_json)
    end

    session[:user_id] = user.id
    redirect_to root_path
  end

  def destroy
    RedisPool.with do |redis|
      redis.del(session[:user_id]) if session[:user_id]
    end
    reset_session
    redirect_to root_path
  end

  protected

  def auth_hash
    request.env['omniauth.auth']
  end
end
