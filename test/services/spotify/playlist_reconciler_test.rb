# frozen_string_literal: true

require 'test_helper'

module Spotify
  class PlaylistReconcilerTest < ActiveSupport::TestCase
    setup do
      @original = Original.create!(code: 'TEST_ORIG_RECON', title: '照合作品', short_title: '照合作品',
                                   original_type: :windows, series_order: 9970)
      @song = OriginalSong.create!(code: 'TEST_SONG_RECON', original_code: @original.code,
                                   title: '照合原曲', track_number: 1, is_duplicate: false)
      @session = SpotifyApi::UserSession.new(
        { 'uid' => 'test-user',
          'credentials' => { 'token' => 'USER_TOKEN', 'refresh_token' => 'REFRESH_TOKEN',
                             'expires_at' => 1.hour.from_now.to_i } }
      )
    end

    def create_spotify_candidate(spotify_id:, jan_code:, isrc:, active:)
      album = Album.create!(jan_code:)
      spotify_album = SpotifyAlbum.create!(album:, spotify_id: "SALBUM-#{spotify_id}", album_type: 'album',
                                           name: "照合アルバム #{spotify_id}", label: Album::TOUHOU_MUSIC_LABEL,
                                           active:)
      track = Track.create!(album:, isrc:)
      TracksOriginalSong.create!(track:, original_song_code: @song.code)
      SpotifyTrack.create!(track:, album:, spotify_album:, spotify_id:, name: "照合曲 #{spotify_id}",
                           label: Album::TOUHOU_MUSIC_LABEL)
    end

    def stub_current_items(spotify_ids)
      stub_spotify_get('playlists/PL_RECON/tracks', body: {
                         'items' => spotify_ids.map { |spotify_id| { 'track' => { 'id' => spotify_id } } },
                         'total' => spotify_ids.size,
                         'limit' => 100,
                         'offset' => 0,
                         'next' => nil
                       }, query: { 'limit' => '100', 'offset' => '0' })
    end

    test 'reports stale IDs and semantic duplicates without writing in dry-run mode' do
      # 同じISRCを別Trackレコードとして持つ候補も、activeなSpotify IDへ正規化する。
      create_spotify_candidate(spotify_id: 'OLD_ID', jan_code: 'JAN-OLD', isrc: 'ISRC-SAME', active: false)
      create_spotify_candidate(spotify_id: 'NEW_ID', jan_code: 'JAN-NEW', isrc: 'ISRC-SAME', active: true)
      create_spotify_candidate(spotify_id: 'OTHER_ID', jan_code: 'JAN-OTHER', isrc: 'ISRC-OTHER', active: true)
      stub_current_items(%w[OLD_ID NEW_ID OTHER_ID])

      result = PlaylistReconciler.new(session: @session, playlist_id: 'PL_RECON', original_song: @song).call

      assert_equal :would_repair, result.status
      assert_equal %w[spotify:track:OLD_ID spotify:track:NEW_ID spotify:track:OTHER_ID], result.current_uris
      assert_equal %w[spotify:track:OTHER_ID spotify:track:NEW_ID], result.desired_uris
      assert_equal 1, result.extra_count
      assert_equal 0, result.missing_count
      assert_equal 0, result.exact_duplicate_count
      assert_equal 1, result.semantic_duplicate_group_count
      assert_not_requested :put, %r{/playlists/PL_RECON/(tracks|items)}
    end

    test 'never clears a playlist when the DB has no Spotify candidates' do
      stub_current_items(['OLD_ID'])

      result = PlaylistReconciler.new(session: @session, playlist_id: 'PL_RECON', original_song: @song,
                                      apply: true).call

      assert_equal :skipped_empty, result.status
      assert_not_requested :put, %r{/playlists/PL_RECON/(tracks|items)}
      assert_not_requested :post, %r{/playlists/PL_RECON/(tracks|items)}
    end

    test 'repairs only after apply is explicitly enabled and verifies the result' do
      create_spotify_candidate(spotify_id: 'OLD_ID', jan_code: 'JAN-OLD', isrc: 'ISRC-SAME', active: false)
      create_spotify_candidate(spotify_id: 'NEW_ID', jan_code: 'JAN-NEW', isrc: 'ISRC-SAME', active: true)
      url = "#{SpotifyApiStubs::API_BASE}/playlists/PL_RECON/tracks"
      stub_request(:get, url).with(query: { 'limit' => '100', 'offset' => '0' }).to_return(
        { status: 200, body: {
          'items' => [{ 'track' => { 'id' => 'OLD_ID' } }], 'total' => 1,
          'limit' => 100, 'offset' => 0, 'next' => nil
        }.to_json, headers: SpotifyApiStubs::JSON_HEADERS },
        { status: 200, body: {
          'items' => [{ 'track' => { 'id' => 'NEW_ID' } }], 'total' => 1,
          'limit' => 100, 'offset' => 0, 'next' => nil
        }.to_json, headers: SpotifyApiStubs::JSON_HEADERS }
      )
      stub_spotify_put('playlists/PL_RECON/tracks', body: { 'snapshot_id' => 'snap' })

      result = PlaylistReconciler.new(session: @session, playlist_id: 'PL_RECON', original_song: @song,
                                      apply: true).call

      assert_equal :repaired, result.status
      assert_requested :put, url do |request|
        JSON.parse(request.body)['uris'] == ['spotify:track:NEW_ID']
      end
    end
  end
end
