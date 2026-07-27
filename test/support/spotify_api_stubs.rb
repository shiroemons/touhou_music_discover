# frozen_string_literal: true

# Spotify Web API を WebMock でスタブするためのヘルパ。
#
# fixture は test/fixtures/files/spotify_api/ に置いた合成値の JSON。
# 実 API のレスポンス形状に合わせてあるが、トークン・メールアドレス・
# プレイリスト名はすべて架空の値に置き換えてある。
module SpotifyApiStubs
  API_BASE = 'https://api.spotify.com/v1'
  ACCOUNTS_BASE = 'https://accounts.spotify.com'
  JSON_HEADERS = { 'Content-Type' => 'application/json' }.freeze

  def spotify_fixture(name)
    Rails.root.join("test/fixtures/files/spotify_api/#{name}.json").read
  end

  def spotify_fixture_hash(name)
    JSON.parse(spotify_fixture(name))
  end

  def stub_spotify_get(path, body:, status: 200, query: nil)
    stub = stub_request(:get, "#{API_BASE}/#{path}")
    stub = stub.with(query:) if query
    stub.to_return(status:, body: normalize_body(body), headers: JSON_HEADERS)
  end

  def stub_spotify_post(path, body: {}, status: 200)
    stub_request(:post, "#{API_BASE}/#{path}")
      .to_return(status:, body: normalize_body(body), headers: JSON_HEADERS)
  end

  def stub_spotify_put(path, body: {}, status: 200)
    stub_request(:put, "#{API_BASE}/#{path}")
      .to_return(status:, body: normalize_body(body), headers: JSON_HEADERS)
  end

  def stub_spotify_delete(path, body: {}, status: 200)
    stub_request(:delete, "#{API_BASE}/#{path}")
      .to_return(status:, body: normalize_body(body), headers: JSON_HEADERS)
  end

  # 429 応答。Retry-After を秒で指定する。
  def stub_spotify_rate_limited(method, path, retry_after: 1)
    stub_request(method, "#{API_BASE}/#{path}")
      .to_return(status: 429, body: '{}',
                 headers: JSON_HEADERS.merge('Retry-After' => retry_after.to_s))
  end

  def stub_spotify_token_refresh(access_token: 'NEW_ACCESS_TOKEN', expires_in: 3600)
    stub_request(:post, "#{ACCOUNTS_BASE}/api/token")
      .to_return(status: 200,
                 body: { access_token:, token_type: 'Bearer', expires_in: }.to_json,
                 headers: JSON_HEADERS)
  end

  private

  def normalize_body(body)
    body.is_a?(String) ? body : body.to_json
  end
end
