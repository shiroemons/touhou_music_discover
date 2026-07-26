# frozen_string_literal: true

require 'test_helper'

module SpotifyApi
  class TrackTest < ActiveSupport::TestCase
    JSON_HEADERS = { 'Content-Type' => 'application/json' }.freeze
    FakeConfig = Struct.new(:access_token, :adapter)

    setup do
      @stubs = Faraday::Adapter::Test::Stubs.new
      Track.client = build_client
    end

    teardown do
      # 差し込んだ Client がテスト間で漏れないよう、必ずリセットする。
      Track.reset_client!
    end

    test 'find does not send a market parameter by default' do
      query = capture_query('/v1/tracks/123', { id: '123' })

      Track.find('123')

      assert_nil query[:value]
    end

    test 'find sends market only when explicitly given' do
      query = capture_query('/v1/tracks/123', { id: '123' })

      Track.find('123', market: 'JP')

      assert_equal 'market=JP', query[:value]
    end

    test 'find wraps the response body' do
      @stubs.get('/v1/tracks/123') { [200, JSON_HEADERS, { id: '123', name: 'track' }.to_json] }

      track = Track.find('123')

      assert_instance_of Response, track
      assert_equal 'track', track.name
    end

    test 'find_many fetches each id individually instead of using the bulk endpoint' do
      @stubs.get('/v1/tracks/1') { [200, JSON_HEADERS, { id: '1' }.to_json] }
      @stubs.get('/v1/tracks/2') { [200, JSON_HEADERS, { id: '2' }.to_json] }

      tracks = Track.find_many(%w[1 2])

      assert_equal %w[1 2], tracks.map(&:id)
    end

    test 'find_many skips ids that respond with 404' do
      @stubs.get('/v1/tracks/1') { [200, JSON_HEADERS, { id: '1' }.to_json] }
      @stubs.get('/v1/tracks/2') { [404, JSON_HEADERS, { error: { status: 404, message: 'not found' } }.to_json] }

      tracks = Track.find_many(%w[1 2])

      assert_equal ['1'], tracks.map(&:id)
    end

    test 'find_many propagates errors other than 404, such as rate limiting' do
      @stubs.get('/v1/tracks/1') { [429, JSON_HEADERS, { error: { status: 429, message: 'rate limited' } }.to_json] }

      assert_raises(RateLimitError) { Track.find_many(%w[1]) }
    end

    private

    def build_client
      connection = Faraday.new(url: Config::API_URL) do |conn|
        conn.request :json
        conn.response :json, content_type: /\bjson$/
        conn.adapter :test, @stubs
      end

      Client.new(FakeConfig.new('TOKEN', :test), connection:)
    end

    def capture_query(path, body)
      query = {}
      @stubs.get(path) do |env|
        query[:value] = env.url.query
        [200, JSON_HEADERS, body.to_json]
      end
      query
    end
  end
end
