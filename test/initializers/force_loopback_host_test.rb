# frozen_string_literal: true

require 'test_helper'

class ForceLoopbackHostTest < ActiveSupport::TestCase
  # 内側の Rack アプリが呼ばれたかどうかを記録するスタブ。
  class FakeApp
    attr_reader :call_count

    def initialize
      @call_count = 0
    end

    def called?
      @call_count.positive?
    end

    def call(_env)
      @call_count += 1
      [200, { 'content-type' => 'text/plain' }, ['ok']]
    end
  end

  setup do
    @app = FakeApp.new
    @middleware = ForceLoopbackHost.new(@app)
  end

  test 'localhost へのリクエストを 127.0.0.1 へ 302 リダイレクトする' do
    status, headers, = @middleware.call(Rack::MockRequest.env_for('http://localhost:3000/spotify/playlists'))

    assert_equal 302, status
    assert_equal 'http://127.0.0.1:3000/spotify/playlists', headers['location']
    assert_not @app.called?
  end

  test 'リダイレクト先にクエリ文字列を引き継ぐ' do
    _status, headers, = @middleware.call(Rack::MockRequest.env_for('http://localhost:3000/x?a=1&b=2'))

    assert_equal 'http://127.0.0.1:3000/x?a=1&b=2', headers['location']
  end

  test '127.0.0.1 へのリクエストはそのまま通す' do
    status, = @middleware.call(Rack::MockRequest.env_for('http://127.0.0.1:3000/spotify/playlists'))

    assert_equal 200, status
    assert_equal 1, @app.call_count
  end

  test 'localhost 以外のホストへのリクエストはそのまま通す' do
    status, = @middleware.call(Rack::MockRequest.env_for('http://example.test/spotify/playlists'))

    assert_equal 200, status
    assert_equal 1, @app.call_count
  end

  test 'POST も 302 でリダイレクトする' do
    env = Rack::MockRequest.env_for('http://localhost:3000/auth/spotify', method: 'POST')

    status, headers, = @middleware.call(env)

    assert_equal 302, status
    assert_equal 'http://127.0.0.1:3000/auth/spotify', headers['location']
    assert_not @app.called?
  end
end
