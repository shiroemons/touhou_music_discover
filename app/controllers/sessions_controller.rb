# frozen_string_literal: true

class SessionsController < ApplicationController
  def create
    user = User.find_or_create_from_auth_hash(auth_hash)
    RedisPool.with do |redis|
      redis.set(user.id, auth_hash.to_json)
    end

    session[:user_id] = user.id
    redirect_to root_path
  end

  def destroy
    redis = RedisPool.get
    redis.del(session[:user_id])
    reset_session
    redirect_to root_path
  end

  protected

  def auth_hash
    request.env['omniauth.auth']
  end
end
