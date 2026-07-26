# frozen_string_literal: true

require 'test_helper'

module Spotify
  class PlaylistUpdateServiceTest < ActiveSupport::TestCase
    setup do
      @original = Original.create!(code: 'TEST_ORIG_SVC', title: 'テスト作品', short_title: 'テスト作品',
                                   original_type: :windows, series_order: 9980)
      @song = OriginalSong.create!(code: 'TEST_SONG_SVC', original_code: @original.code,
                                   title: 'サービステスト原曲', track_number: 1, is_duplicate: false)
      create_spotify_track(@song, 'SVCTRACK1')

      @user_id = SecureRandom.uuid
      @session = SpotifyApi::UserSession.new(
        { 'uid' => 'test-user',
          'credentials' => { 'token' => 'USER_TOKEN', 'refresh_token' => 'REFRESH_TOKEN',
                             'expires_at' => 1.hour.from_now.to_i } }
      )
      RedisPool.with { |r| r.set(progress_key, { 'status' => 'processing' }.to_json) }
    end

    teardown do
      RedisPool.with { |r| r.del(progress_key) }
    end

    # 原曲に紐づく SpotifyTrack を1件作る。Album は jan_code (unique, NOT NULL) のみ、
    # Track は album (jan_code経由) と isrc が必須、SpotifyTrack は album/spotify_album/track の
    # belongs_to と label が必須なため、サービスがたどる through 関連を素通りできる
    # 最小限のレコードを組み立てる。
    def create_spotify_track(song, spotify_id)
      album = Album.create!(jan_code: "JAN-#{spotify_id}")
      spotify_album = SpotifyAlbum.create!(album:, spotify_id: "SALBUM-#{spotify_id}", album_type: 'album',
                                           name: "テストアルバム #{spotify_id}", label: Album::TOUHOU_MUSIC_LABEL)
      track = Track.create!(album:, isrc: "ISRC-#{spotify_id}")
      TracksOriginalSong.create!(track:, original_song_code: song.code)
      SpotifyTrack.create!(track:, album:, spotify_album:, spotify_id:, name: "テスト曲 #{spotify_id}",
                           label: Album::TOUHOU_MUSIC_LABEL)
    end

    # SpotifyTrack が1件も紐づかない原曲。プレイリスト書き込みの対象外であることを固定するために使う。
    def create_song_without_tracks
      OriginalSong.create!(code: 'TEST_SONG_SVC_EMPTY', original_code: @original.code,
                           title: 'サービステスト原曲（曲なし）', track_number: 2, is_duplicate: false)
    end

    # SpotifyTrack が紐づく2曲目の原曲。「全曲の書き込みが失敗する」状況を作るために使う。
    def create_second_song_with_track
      song = OriginalSong.create!(code: 'TEST_SONG_SVC_2', original_code: @original.code,
                                  title: 'サービステスト原曲2', track_number: 3, is_duplicate: false)
      create_spotify_track(song, 'SVCTRACK2')
      song
    end

    def progress_key
      "playlist_update:#{@user_id}"
    end

    def progress
      JSON.parse(RedisPool.with { |r| r.get(progress_key) })
    end

    def playlists_body(items)
      { 'items' => items, 'total' => items.size, 'limit' => 50, 'offset' => 0, 'next' => nil }
    end

    def playlist_item(id, name)
      { 'id' => id, 'name' => name, 'tracks' => { 'total' => 0 },
        'external_urls' => { 'spotify' => "https://open.spotify.com/playlist/#{id}" } }
    end

    def stub_me_playlists(items)
      stub_spotify_get('me/playlists', body: playlists_body(items),
                                       query: { 'limit' => '50', 'offset' => '0' })
    end

    # 403 は SpotifyRetry がリトライしない非リトライ 4xx なので、テストがスリープしない。
    def stub_forbidden_put(path)
      stub_spotify_put(path, status: 403, body: { error: { status: 403, message: 'Forbidden.' } })
    end

    def call_service
      PlaylistUpdateService.call(update_type: 'windows', spotify_session: @session, user_id: @user_id)
    end

    test 'creates a playlist when none exists and replaces its items' do
      stub_me_playlists([])
      stub_spotify_post('me/playlists', body: { 'id' => 'PL_NEW', 'name' => @song.title })
      stub_spotify_put('playlists/PL_NEW/tracks', body: { 'snapshot_id' => 'snap' })

      call_service

      assert_requested :post, "#{SpotifyApiStubs::API_BASE}/me/playlists" do |req|
        JSON.parse(req.body)['name'] == @song.title
      end
      assert_requested :put, "#{SpotifyApiStubs::API_BASE}/playlists/PL_NEW/tracks" do |req|
        JSON.parse(req.body)['uris'] == ['spotify:track:SVCTRACK1']
      end
      assert_equal 'completed', progress['status']
    end

    test 'reuses an existing playlist instead of creating a duplicate' do
      stub_me_playlists([playlist_item('PL_EXISTING', @song.title)])
      put_stub = stub_spotify_put('playlists/PL_EXISTING/tracks', body: { 'snapshot_id' => 'snap' })

      call_service

      assert_requested put_stub
      assert_not_requested :post, "#{SpotifyApiStubs::API_BASE}/me/playlists"
    end

    # PlaylistTrackWriter は PUT {"uris": []} でプレイリストの中身を空にする。
    # 曲が1件も無い原曲に対してこれを発行すると、既存プレイリストを実際に全消しする
    # 破壊的操作になるため、書き込み経路に到達しないことを固定する。
    test 'never writes to a playlist for an original song that has no spotify tracks' do
      empty_song = create_song_without_tracks
      stub_me_playlists([playlist_item('PL_EXISTING', @song.title),
                         playlist_item('PL_EMPTY', empty_song.title)])
      stub_spotify_put('playlists/PL_EXISTING/tracks', body: { 'snapshot_id' => 'snap' })

      call_service

      assert_equal 'completed', progress['status']
      assert_not_requested :put, "#{SpotifyApiStubs::API_BASE}/playlists/PL_EMPTY/tracks"
      assert_not_requested :post, "#{SpotifyApiStubs::API_BASE}/playlists/PL_EMPTY/tracks"
      assert_not_requested :delete, "#{SpotifyApiStubs::API_BASE}/playlists/PL_EMPTY/tracks"
    end

    # 曲が無い原曲はプレイリストの新規作成対象にもならない（空のプレイリストを量産しない）。
    test 'does not create a playlist for an original song that has no spotify tracks' do
      create_song_without_tracks
      stub_me_playlists([playlist_item('PL_EXISTING', @song.title)])
      stub_spotify_put('playlists/PL_EXISTING/tracks', body: { 'snapshot_id' => 'snap' })

      call_service

      assert_not_requested :post, "#{SpotifyApiStubs::API_BASE}/me/playlists"
    end

    # クォータ超過は待っても回復しないため、握りつぶさず処理全体を止める。
    # 429 + QUOTA_EXCEEDED は SpotifyRetry が即座に再送出するのでテストも待たされない。
    test 'marks progress as error and re-raises when the quota is exhausted' do
      stub_me_playlists([])
      stub_request(:post, "#{SpotifyApiStubs::API_BASE}/me/playlists")
        .to_return(status: 429,
                   body: { error: { status: 429, reason: 'QUOTA_EXCEEDED', message: 'quota' } }.to_json,
                   headers: { 'Content-Type' => 'application/json', 'Retry-After' => '7200' })

      assert_raises(SpotifyApi::QuotaExceededError) { call_service }

      assert_equal 'error', progress['status']
    end

    # 1曲の失敗で全体を止めないため、クォータ超過以外のエラーはログに残して次の曲へ進む。
    test 'logs and skips a song that fails with a non-quota error' do
      stub_me_playlists([])
      stub_spotify_post('me/playlists', body: { error: { status: 403, message: 'Forbidden.' } }, status: 403)

      call_service

      assert_equal 'completed', progress['status']
      assert_not_requested :put, %r{/playlists/.*/tracks}
    end

    # 全曲の書き込みが失敗しても、例外は曲ごとに握りつぶされるため run は completed で終わる。
    # 「完了しました」だけでは何も書けていないことが分からないので、失敗の実態が
    # 進捗情報に残ることを固定する。
    test 'records every failed song in the progress info even though the run completes' do
      second_song = create_second_song_with_track
      stub_me_playlists([playlist_item('PL_EXISTING', @song.title),
                         playlist_item('PL_EXISTING_2', second_song.title)])
      stub_forbidden_put('playlists/PL_EXISTING/tracks')
      stub_forbidden_put('playlists/PL_EXISTING_2/tracks')

      call_service

      assert_equal 'completed', progress['status']
      assert_equal 2, progress['failed_count']
      assert_match 'SpotifyApi::ForbiddenError', progress['last_error_message']
    end

    # 一覧取得が失敗したら、曲ごとにリロードを繰り返さず run 全体を即座に error にする。
    test 'fails the whole run when the playlist list cannot be loaded' do
      stub_spotify_get('me/playlists', status: 403,
                                       body: { error: { status: 403, message: 'Forbidden.' } },
                                       query: { 'limit' => '50', 'offset' => '0' })

      assert_raises(SpotifyApi::ForbiddenError) { call_service }

      assert_equal 'error', progress['status']
      assert_not_requested :post, "#{SpotifyApiStubs::API_BASE}/me/playlists"
      assert_requested :get, "#{SpotifyApiStubs::API_BASE}/me/playlists",
                       query: { 'limit' => '50', 'offset' => '0' }, times: 1
    end

    # POST /me/playlists は非冪等なので、タイムアウトしても再送してはならない
    # （再送すると同名の空プレイリストが増える）。
    test 'does not retry the non-idempotent playlist creation' do
      stub_me_playlists([])
      stub_request(:post, "#{SpotifyApiStubs::API_BASE}/me/playlists").to_timeout

      call_service

      assert_requested :post, "#{SpotifyApiStubs::API_BASE}/me/playlists", times: 1
    end
  end
end
