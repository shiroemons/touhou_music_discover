# frozen_string_literal: true

require 'test_helper'

module SpotifyApi
  class AudioFeaturesTest < ActiveSupport::TestCase
    JSON_HEADERS = { 'Content-Type' => 'application/json' }.freeze
    FakeConfig = Struct.new(:access_token, :adapter)

    setup do
      @stubs = Faraday::Adapter::Test::Stubs.new
      AudioFeatures.client = build_client
    end

    teardown do
      # 差し込んだ Client がテスト間で漏れないよう、必ずリセットする。
      AudioFeatures.reset_client!
    end

    test 'find wraps the response body' do
      @stubs.get('/v1/audio-features/1') { [200, JSON_HEADERS, { id: '1', tempo: 120.0 }.to_json] }

      features = AudioFeatures.find('1')

      assert_instance_of Response, features
      assert_equal 120.0, features.tempo
    end

    test 'find returns nil and does not raise when the endpoint responds with 403' do
      @stubs.get('/v1/audio-features/1') { [403, JSON_HEADERS, { error: { status: 403, message: 'forbidden' } }.to_json] }

      assert_nil AudioFeatures.find('1')
    end

    test 'find returns nil and does not raise when the endpoint responds with 404' do
      @stubs.get('/v1/audio-features/1') { [404, JSON_HEADERS, { error: { status: 404, message: 'not found' } }.to_json] }

      assert_nil AudioFeatures.find('1')
    end

    test 'find propagates rate limit errors instead of swallowing them' do
      @stubs.get('/v1/audio-features/1') { [429, JSON_HEADERS, { error: { status: 429, message: 'rate limited' } }.to_json] }

      assert_raises(RateLimitError) { AudioFeatures.find('1') }
    end

    test 'find_many splits ids into batches of 100' do
      ids = (1..150).map { |i| "id#{i}" }
      queries = []
      @stubs.get('/v1/audio-features') do |env|
        queries << env.url.query
        [200, JSON_HEADERS, { audio_features: [] }.to_json]
      end

      AudioFeatures.find_many(ids)

      assert_equal 2, queries.size
      assert_equal ids.first(100), requested_ids(queries[0])
      assert_equal ids.last(50), requested_ids(queries[1])
    end

    test 'find_many excludes null entries from the response' do
      @stubs.get('/v1/audio-features') do
        [200, JSON_HEADERS, { audio_features: [{ id: '1' }, nil, { id: '2' }] }.to_json]
      end

      features = AudioFeatures.find_many(%w[1 2])

      assert_equal %w[1 2], features.map(&:id)
    end

    test 'find_many returns an empty array and does not raise when the endpoint responds with 403' do
      @stubs.get('/v1/audio-features') { [403, JSON_HEADERS, { error: { status: 403, message: 'forbidden' } }.to_json] }

      assert_equal [], AudioFeatures.find_many(%w[1 2])
    end

    test 'find_many returns an empty array and does not raise when the endpoint responds with 404' do
      @stubs.get('/v1/audio-features') { [404, JSON_HEADERS, { error: { status: 404, message: 'not found' } }.to_json] }

      assert_equal [], AudioFeatures.find_many(%w[1 2])
    end

    test 'find_many propagates rate limit errors instead of swallowing them' do
      @stubs.get('/v1/audio-features') { [429, JSON_HEADERS, { error: { status: 429, message: 'rate limited' } }.to_json] }

      assert_raises(RateLimitError) { AudioFeatures.find_many(%w[1 2]) }
    end

    private

    def requested_ids(query)
      URI.decode_www_form(query).to_h['ids'].split(',')
    end

    def build_client
      connection = Faraday.new(url: Config::API_URL) do |conn|
        conn.request :json
        conn.response :json, content_type: /\bjson$/
        conn.adapter :test, @stubs
      end

      Client.new(FakeConfig.new('TOKEN', :test), connection:)
    end
  end
end
