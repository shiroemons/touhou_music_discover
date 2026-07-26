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
  end
end
