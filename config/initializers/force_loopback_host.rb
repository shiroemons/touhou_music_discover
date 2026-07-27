# frozen_string_literal: true

# Spotify は OAuth の redirect URI に localhost を許可しておらず、明示的な
# ループバックアドレス (http://127.0.0.1:PORT) を要求する。
# redirect_uri はリクエストのホストから組み立てられるため、localhost でアクセス
# したままログインすると "redirect_uri: Not matching configuration" になる。
#
# さらに localhost と 127.0.0.1 は Cookie の観点では別ホストなので、両者を
# 行き来するとセッションが分断され「ログインしたのに未ログイン扱い」になる。
# そのため一部だけ寄せるのではなく、development では全リクエストを
# 127.0.0.1 に寄せて localhost 側にセッションが作られないようにする。
#
# 302 を使う。307 はメソッドを保持するが、localhost で描画されたフォームの
# CSRF トークンは 127.0.0.1 のセッションと一致しないため POST が弾かれる。
# 全リクエストを寄せていればフォーム自体が 127.0.0.1 で描画されるので、
# メソッドを保持する必要がない。
class ForceLoopbackHost
  REDIRECTED_HOST = 'localhost'
  LOOPBACK_HOST = '127.0.0.1'

  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)
    return @app.call(env) unless request.host == REDIRECTED_HOST

    url = loopback_url(request)
    [302, { 'location' => url, 'content-type' => 'text/plain' }, ["Redirecting to #{url}"]]
  end

  private

  def loopback_url(request)
    uri = URI.parse(request.url)
    uri.host = LOOPBACK_HOST
    uri.to_s
  end
end

Rails.application.config.middleware.insert_before(0, ForceLoopbackHost) if Rails.env.development?
