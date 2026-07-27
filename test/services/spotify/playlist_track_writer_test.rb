# frozen_string_literal: true

require 'test_helper'

module Spotify
  class PlaylistTrackWriterTest < ActiveSupport::TestCase
    SpotifyTrackStub = Struct.new(:spotify_id)

    setup do
      @session = SpotifyApi::UserSession.new(
        { 'uid' => 'test-user',
          'credentials' => { 'token' => 'USER_TOKEN', 'refresh_token' => 'R',
                             'expires_at' => 1.hour.from_now.to_i } }
      )
    end

    def tracks(count)
      Array.new(count) { |i| SpotifyTrackStub.new(format('TRACK%03d', i)) }
    end

    test 'replaces the playlist with a single PUT when within the batch limit' do
      stub_spotify_put('playlists/PL1/tracks', body: { 'snapshot_id' => 'snap' })

      written = PlaylistTrackWriter.call(session: @session, playlist_id: 'PL1',
                                         spotify_tracks: tracks(3), source: 'test')

      assert_equal 3, written
      # このWebMockのバージョンでは assert_requested(stub) { ... } はブロックを受け付けないため、
      # メソッド+URLの形式でリクエスト内容を検証する。
      assert_requested :put, "#{SpotifyApiStubs::API_BASE}/playlists/PL1/tracks" do |req|
        JSON.parse(req.body)['uris'] == %w[spotify:track:TRACK000 spotify:track:TRACK001
                                           spotify:track:TRACK002]
      end
      assert_not_requested :post, "#{SpotifyApiStubs::API_BASE}/playlists/PL1/tracks"
    end

    # 「PUT 1回 + POST 2回」だけを見る検証では、トラックの重複・欠落や
    # PUT が POST の後に来る（= 先に足した分が消える）実装でもテストが通ってしまう。
    # 呼び出し順・各リクエストの件数・全体の並びまで固定して、このクラスの
    # 存在理由である「PUT が先、以降は POST」を壊せないようにする。
    test 'PUTs the first 100 then POSTs the remainder in order, with no duplicates or gaps' do
      calls = []
      url = "#{SpotifyApiStubs::API_BASE}/playlists/PL1/tracks"
      stub_request(:put, url).to_return do |req|
        calls << [:put, JSON.parse(req.body)['uris']]
        { status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' } }
      end
      stub_request(:post, url).to_return do |req|
        calls << [:post, JSON.parse(req.body)['uris']]
        { status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' } }
      end

      written = PlaylistTrackWriter.call(session: @session, playlist_id: 'PL1',
                                         spotify_tracks: tracks(250), source: 'test')

      batch_sizes = calls.map { |(_, uris)| uris.size }
      expected_uris = tracks(250).map { |track| "spotify:track:#{track.spotify_id}" }

      assert_equal 250, written
      assert_equal %i[put post post], calls.map(&:first)
      assert_equal [100, 100, 50], batch_sizes
      assert_equal expected_uris, calls.flat_map(&:last)
    end

    test 'clears the playlist with an empty uris array when there are no tracks and allow_clear is true' do
      stub_spotify_put('playlists/PL1/tracks', body: { 'snapshot_id' => 'snap' })

      written = PlaylistTrackWriter.call(session: @session, playlist_id: 'PL1',
                                         spotify_tracks: [], source: 'test', allow_clear: true)

      assert_equal 0, written
      assert_requested :put, "#{SpotifyApiStubs::API_BASE}/playlists/PL1/tracks" do |req|
        JSON.parse(req.body)['uris'] == []
      end
      assert_not_requested :post, "#{SpotifyApiStubs::API_BASE}/playlists/PL1/tracks"
    end

    # allow_clear の既定値は false。将来どこかの呼び出し元が空判定を怠っても、
    # このクラス自身が全消し PUT を拒否することを固定する。
    test 'refuses to clear the playlist with an empty uris array unless allow_clear is true' do
      assert_raises(ArgumentError) do
        PlaylistTrackWriter.call(session: @session, playlist_id: 'PL1', spotify_tracks: [], source: 'test')
      end
      assert_not_requested :put, "#{SpotifyApiStubs::API_BASE}/playlists/PL1/tracks"
    end
  end
end
