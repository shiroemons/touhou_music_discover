# frozen_string_literal: true

require 'test_helper'

module Spotify
  class PlaylistsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @original = Original.create!(code: 'TEST_ORIG_PC', title: 'テスト作品', short_title: 'テスト作品',
                                   original_type: :windows, series_order: 9990)
      @song = OriginalSong.create!(code: 'TEST_SONG_PC', original_code: @original.code,
                                   title: 'テスト原曲', track_number: 1, is_duplicate: false)
      @user = User.create!(provider: 'spotify', uid: 'test-user', name: 'test-user',
                           nickname: 'Test User', email: 'test@example.com', image_url: '')
      store_auth_hash
    end

    teardown do
      RedisPool.with { |r| r.del(@user.id, "playlist_update:#{@user.id}", "refresh_counts:#{@user.id}") }
    end

    def store_auth_hash(expires_at: 1.hour.from_now.to_i)
      hash = {
        'provider' => 'spotify', 'uid' => 'test-user',
        'info' => { 'id' => 'test-user', 'display_name' => 'Test User' },
        'credentials' => { 'token' => 'USER_TOKEN', 'refresh_token' => 'REFRESH_TOKEN',
                           'expires_at' => expires_at, 'expires' => true }
      }
      RedisPool.with { |r| r.set(@user.id, hash.to_json) }
    end

    def log_in
      post '/test_login', params: { user_id: @user.id }
    end

    def me_playlists_body
      spotify_fixture('me_playlists').gsub('PLAYLIST_TITLE_MATCHED', @song.title)
    end

    # GET /playlists/{id} のレスポンス。sync_single は所有確認をこのエンドポイントで行うため、
    # 名前と owner.id をテストごとに差し替えられるようにする。
    def playlist_detail_body(id: 'PL_MATCHED', name: @song.title, owner_id: 'test-user')
      spotify_fixture('playlist_detail')
        .gsub('PLAYLIST_TITLE_MATCHED', name)
        .gsub('PLAYLIST_OWNER_ID', owner_id)
        .gsub('PLAYLIST_ID', id)
    end

    # @song.code に紐づく SpotifyTrack を1件作る。Album は jan_code (unique, NOT NULL) のみ、
    # Track は album (jan_code経由) と isrc (jan_codeとの複合unique, NOT NULL) が必須、
    # SpotifyTrack は album/spotify_album/track の belongs_to と label が必須なため、
    # sync_single が実際にたどる through 関連を素通りできるよう最小限のレコードを組み立てる。
    def create_spotify_track(spotify_id)
      album = Album.create!(jan_code: "JAN-#{spotify_id}")
      spotify_album = SpotifyAlbum.create!(album:, spotify_id: "SALBUM-#{spotify_id}", album_type: 'album',
                                           name: "テストアルバム #{spotify_id}", label: Album::TOUHOU_MUSIC_LABEL)
      track = Track.create!(album:, isrc: "ISRC-#{spotify_id}")
      TracksOriginalSong.create!(track:, original_song_code: @song.code)
      SpotifyTrack.create!(track:, album:, spotify_album:, spotify_id:, name: "テスト曲 #{spotify_id}",
                           label: Album::TOUHOU_MUSIC_LABEL)
    end

    test 'index redirects to root when not logged in' do
      get spotify_playlists_path

      assert_redirected_to root_url
    end

    test 'index redirects to root when the session has no stored Spotify credentials' do
      log_in
      RedisPool.with { |r| r.del(@user.id) }

      get spotify_playlists_path

      assert_redirected_to root_url
    end

    test 'index fetches playlists from Spotify and stores only original-song ones' do
      log_in
      stub = stub_spotify_get('me/playlists', body: me_playlists_body,
                                              query: { 'limit' => '50', 'offset' => '0' })

      get spotify_playlists_path

      assert_response :success
      assert_requested stub
      assert_equal ['PL_MATCHED'], SpotifyPlaylist.pluck(:spotify_id)
      assert_equal @song.code, SpotifyPlaylist.first.original_song_code
      assert_equal 7, SpotifyPlaylist.first.total
    end

    test 'index does not issue per-playlist requests for follower counts' do
      log_in
      stub_spotify_get('me/playlists', body: me_playlists_body,
                                       query: { 'limit' => '50', 'offset' => '0' })

      get spotify_playlists_path

      assert_response :success
      assert_not_requested :get, "#{SpotifyApiStubs::API_BASE}/playlists/PL_MATCHED"
    end

    test 'index shows follower counts from the database' do
      log_in
      SpotifyPlaylist.create!(spotify_id: 'PL_MATCHED', spotify_user_id: 'test-user',
                              name: @song.title, followers: 42, total: 7, position: 0)

      get spotify_playlists_path

      assert_response :success
      assert_match '42', @response.body
      assert_not_requested :get, %r{/me/playlists}
    end

    test 'save_playlists_to_db updates an existing row instead of leaving it stale' do
      log_in
      SpotifyPlaylist.create!(spotify_id: 'PL_MATCHED', spotify_user_id: 'other-user',
                              name: 'stale name', total: 0, followers: 5, position: 0)
      stub_spotify_get('me/playlists', body: me_playlists_body,
                                       query: { 'limit' => '50', 'offset' => '0' })

      get spotify_playlists_path

      record = SpotifyPlaylist.find_by(spotify_id: 'PL_MATCHED')

      assert_equal 'test-user', record.spotify_user_id
      assert_equal @song.title, record.name
      assert_equal 7, record.total
    end

    test 'playlists are stored in reverse API order so the view renders them API-order' do
      log_in
      # フィクスチャの3件目 (PL_MATCHED_2) も原曲名と一致させるため、"#{@song.title}_2" という
      # 別タイトルの原曲を用意する（me_playlists_body の gsub がプレースホルダの接頭辞を
      # 共有しているため、この命名で自動的に一致する）。
      OriginalSong.create!(code: 'TEST_SONG_PC_2', original_code: @original.code,
                           title: "#{@song.title}_2", track_number: 2, is_duplicate: false)
      stub_spotify_get('me/playlists', body: me_playlists_body,
                                       query: { 'limit' => '50', 'offset' => '0' })

      get spotify_playlists_path

      assert_response :success
      assert_equal %w[PL_MATCHED_2 PL_MATCHED], SpotifyPlaylist.order(:position).pluck(:spotify_id)
    end

    test 'index refreshes an expired token before calling the API' do
      log_in
      store_auth_hash(expires_at: 1.hour.ago.to_i)
      token_stub = stub_spotify_token_refresh
      stub_spotify_get('me/playlists', body: me_playlists_body,
                                       query: { 'limit' => '50', 'offset' => '0' })

      get spotify_playlists_path

      assert_response :success
      assert_requested token_stub
      stored = JSON.parse(RedisPool.with { |r| r.get(@user.id) })

      assert_equal 'NEW_ACCESS_TOKEN', stored.dig('credentials', 'token')
    end

    test 'clear_cache deletes cached playlists for the user' do
      log_in
      SpotifyPlaylist.create!(spotify_id: 'PL_MATCHED', spotify_user_id: 'test-user',
                              name: @song.title, position: 0)

      delete spotify_clear_playlists_cache_path

      assert_redirected_to spotify_playlists_path
      assert_equal 0, SpotifyPlaylist.for_user('test-user').count
    end

    test 'clear_cache redirects to root when not logged in' do
      delete spotify_clear_playlists_cache_path

      assert_redirected_to root_url
    end

    test 'sync_single replaces playlist items with the original song tracks' do
      log_in
      create_spotify_track('TRACK1')
      playlist = SpotifyPlaylist.create!(spotify_id: 'PL_MATCHED', spotify_user_id: 'test-user',
                                         name: @song.title, total: 7, position: 0)
      stub_spotify_get('playlists/PL_MATCHED', body: playlist_detail_body)
      stub_spotify_put('playlists/PL_MATCHED/tracks', body: { snapshot_id: 'snap3' })

      post spotify_playlist_sync_path(id: 'PL_MATCHED', name: @song.title)

      assert_redirected_to spotify_playlists_path
      # このWebMockのバージョンでは assert_requested(stub) { ... } はブロックを受け付けないため、
      # メソッド+URLの形式でリクエストボディを検証する。
      assert_requested :put, "#{SpotifyApiStubs::API_BASE}/playlists/PL_MATCHED/tracks" do |req|
        JSON.parse(req.body)['uris'] == ['spotify:track:TRACK1']
      end
      # 1曲しかないので追加の POST は起きてはならない（起きていれば二重登録になる）。
      assert_not_requested :post, "#{SpotifyApiStubs::API_BASE}/playlists/PL_MATCHED/tracks"
      playlist.reload

      assert_equal 1, playlist.total
      assert_not_nil playlist.synced_at
    end

    test 'sync_single does not scan every page of me/playlists' do
      log_in
      create_spotify_track('TRACK1')
      stub_spotify_get('playlists/PL_MATCHED', body: playlist_detail_body)
      stub_spotify_put('playlists/PL_MATCHED/tracks', body: { snapshot_id: 'snap3' })

      post spotify_playlist_sync_path(id: 'PL_MATCHED', name: @song.title)

      assert_redirected_to spotify_playlists_path
      assert_not_requested :get, %r{/me/playlists}
    end

    test 'sync_single refuses a playlist whose name is not an original song' do
      log_in

      post spotify_playlist_sync_path(id: 'PL_UNMATCHED', name: '原曲名ではないプレイリスト')

      assert_redirected_to spotify_playlists_path
      assert_equal '原曲が見つかりません: 原曲名ではないプレイリスト', flash[:alert]
      # 原曲名でない時点で弾かれるため、Spotify への問い合わせ自体が起きない。
      assert_not_requested :get, "#{SpotifyApiStubs::API_BASE}/playlists/PL_UNMATCHED"
      assert_not_requested :put, "#{SpotifyApiStubs::API_BASE}/playlists/PL_UNMATCHED/tracks"
      assert_not_requested :post, "#{SpotifyApiStubs::API_BASE}/playlists/PL_UNMATCHED/tracks"
    end

    test 'sync_single refuses when the id does not belong to the user' do
      log_in
      create_spotify_track('TRACK1')
      stub_spotify_get('playlists/PL_SOMEONE_ELSE', status: 404,
                                                    body: { error: { status: 404, message: 'Not found.' } })

      post spotify_playlist_sync_path(id: 'PL_SOMEONE_ELSE', name: @song.title)

      assert_redirected_to spotify_playlists_path
      assert_equal "プレイリストが見つかりません: #{@song.title}", flash[:alert]
      assert_not_requested :put, "#{SpotifyApiStubs::API_BASE}/playlists/PL_SOMEONE_ELSE/tracks"
      assert_not_requested :post, "#{SpotifyApiStubs::API_BASE}/playlists/PL_SOMEONE_ELSE/tracks"
    end

    test 'sync_single refuses when the id maps to a different playlist name' do
      log_in
      create_spotify_track('TRACK1')
      stub_spotify_get('playlists/PL_UNMATCHED',
                       body: playlist_detail_body(id: 'PL_UNMATCHED', name: '原曲名ではないプレイリスト'))

      post spotify_playlist_sync_path(id: 'PL_UNMATCHED', name: @song.title)

      assert_redirected_to spotify_playlists_path
      assert_equal "プレイリストが見つかりません: #{@song.title}", flash[:alert]
      assert_not_requested :put, "#{SpotifyApiStubs::API_BASE}/playlists/PL_UNMATCHED/tracks"
      assert_not_requested :post, "#{SpotifyApiStubs::API_BASE}/playlists/PL_UNMATCHED/tracks"
    end

    # GET /me/playlists にはフォロー中・共同編集のプレイリストも含まれるため、
    # 「一覧に出る」ことは「自分が所有している」ことの証明にならない。原曲名と同名の
    # 他人のプレイリストを差し替えてしまわないことを固定する。
    test 'sync_single refuses a playlist owned by someone else' do
      log_in
      create_spotify_track('TRACK1')
      stub_spotify_get('playlists/PL_MATCHED', body: playlist_detail_body(owner_id: 'someone-else'))

      post spotify_playlist_sync_path(id: 'PL_MATCHED', name: @song.title)

      assert_redirected_to spotify_playlists_path
      assert_equal "プレイリストが見つかりません: #{@song.title}", flash[:alert]
      # 名前は一致しているので、拒否の理由は所有者不一致以外にありえない。
      assert_requested :get, "#{SpotifyApiStubs::API_BASE}/playlists/PL_MATCHED"
      assert_not_requested :put, "#{SpotifyApiStubs::API_BASE}/playlists/PL_MATCHED/tracks"
      assert_not_requested :post, "#{SpotifyApiStubs::API_BASE}/playlists/PL_MATCHED/tracks"
    end

    # PUT 済みの先頭100件だけが反映された「途中まで書けた」状態を、
    # synced_at を落として記録する（PUT は冪等なので再同期で完全に復旧できる）。
    test 'sync_single clears synced_at when a later batch write fails' do
      log_in
      101.times { |i| create_spotify_track(format('TRACK%03d', i)) }
      playlist = SpotifyPlaylist.create!(spotify_id: 'PL_MATCHED', spotify_user_id: 'test-user',
                                         name: @song.title, total: 7, synced_at: 1.day.ago, position: 0)
      stub_spotify_get('playlists/PL_MATCHED', body: playlist_detail_body)
      stub_spotify_put('playlists/PL_MATCHED/tracks', body: { snapshot_id: 'snap' })
      # 403 は SpotifyRetry がリトライしない非リトライ 4xx なので、テストがスリープしない。
      stub_spotify_post('playlists/PL_MATCHED/tracks', status: 403,
                                                       body: { error: { status: 403, message: 'Forbidden.' } })

      post spotify_playlist_sync_path(id: 'PL_MATCHED', name: @song.title)

      assert_redirected_to spotify_playlists_path
      assert_equal I18n.t('spotify.playlists.alerts.sync_failed'), flash[:alert]
      assert_nil playlist.reload.synced_at
    end

    test 'sync_single reports a rate limit without leaking the raw error message' do
      log_in
      create_spotify_track('TRACK1')
      playlist = SpotifyPlaylist.create!(spotify_id: 'PL_MATCHED', spotify_user_id: 'test-user',
                                         name: @song.title, total: 7, synced_at: 1.day.ago, position: 0)
      stub_spotify_get('playlists/PL_MATCHED', body: playlist_detail_body)
      # Retry-After が max_retry_after(60秒) を超えるため、待たずに即座に再送出される。
      stub_spotify_rate_limited(:put, 'playlists/PL_MATCHED/tracks', retry_after: 3600)

      post spotify_playlist_sync_path(id: 'PL_MATCHED', name: @song.title)

      assert_redirected_to spotify_playlists_path
      assert_equal I18n.t('spotify.playlists.alerts.rate_limited'), flash[:alert]
      assert_nil playlist.reload.synced_at
    end

    test 'sync_single reports a quota exhaustion separately from a plain rate limit' do
      log_in
      create_spotify_track('TRACK1')
      playlist = SpotifyPlaylist.create!(spotify_id: 'PL_MATCHED', spotify_user_id: 'test-user',
                                         name: @song.title, total: 7, synced_at: 1.day.ago, position: 0)
      stub_spotify_get('playlists/PL_MATCHED', body: playlist_detail_body)
      stub_request(:put, "#{SpotifyApiStubs::API_BASE}/playlists/PL_MATCHED/tracks")
        .to_return(status: 429,
                   body: { error: { status: 429, reason: 'QUOTA_EXCEEDED', message: 'quota' } }.to_json,
                   headers: { 'Content-Type' => 'application/json', 'Retry-After' => '7200' })

      post spotify_playlist_sync_path(id: 'PL_MATCHED', name: @song.title)

      assert_redirected_to spotify_playlists_path
      assert_equal I18n.t('spotify.playlists.alerts.quota_exceeded'), flash[:alert]
      assert_nil playlist.reload.synced_at
    end
  end
end
