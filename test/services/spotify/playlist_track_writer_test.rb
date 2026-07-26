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

    test 'PUTs the first 100 then POSTs the remainder in batches of 100' do
      put_stub = stub_spotify_put('playlists/PL1/tracks', body: { 'snapshot_id' => 'snap' })
      post_stub = stub_spotify_post('playlists/PL1/tracks', body: { 'snapshot_id' => 'snap' })

      written = PlaylistTrackWriter.call(session: @session, playlist_id: 'PL1',
                                         spotify_tracks: tracks(250), source: 'test')

      assert_equal 250, written
      assert_requested put_stub, times: 1
      assert_requested post_stub, times: 2
      assert_requested :put, "#{SpotifyApiStubs::API_BASE}/playlists/PL1/tracks" do |req|
        JSON.parse(req.body)['uris'].size == 100
      end
    end

    test 'clears the playlist with an empty uris array when there are no tracks' do
      stub_spotify_put('playlists/PL1/tracks', body: { 'snapshot_id' => 'snap' })

      written = PlaylistTrackWriter.call(session: @session, playlist_id: 'PL1',
                                         spotify_tracks: [], source: 'test')

      assert_equal 0, written
      assert_requested :put, "#{SpotifyApiStubs::API_BASE}/playlists/PL1/tracks" do |req|
        JSON.parse(req.body)['uris'] == []
      end
    end
  end
end
