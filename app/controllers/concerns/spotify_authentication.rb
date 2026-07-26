# frozen_string_literal: true

# Spotify のユーザーセッション（アクセストークン）を解決する before_action。
#
# 従来は各アクションが以下の 3 行をコピペしていた。
#
#   redirect_to root_url unless session[:user_id]   # ← return が無い
#   auth_hash = JSON.parse(redis.get(session[:user_id]))
#   spotify_user = RSpotify::User.new(auth_hash)
#
# 1 行目に return が無いため、未ログインでもリダイレクト後に処理が続行し、
# JSON.parse(nil) が TypeError になっていた。before_action に集約することで
# この穴が構造的に消える。
module SpotifyAuthentication
  extend ActiveSupport::Concern

  private

  attr_reader :spotify_session

  def require_spotify_session
    return redirect_to root_url if session[:user_id].blank?

    @spotify_session = SpotifyApi::UserSession.find(session[:user_id])
    # セッションはあるが Redis に認証情報が無い（期限切れ・ログアウト済み）。
    # RSpotify::User のように「他のユーザーのトークン」へフォールバックしない。
    redirect_to root_url if @spotify_session.nil?
  end

  def spotify_user_id
    spotify_session.spotify_user_id
  end
end
