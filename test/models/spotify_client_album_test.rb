# frozen_string_literal: true

require 'test_helper'

module SpotifyClient
  class AlbumTest < ActiveSupport::TestCase
    SpotifyApiAlbum = Struct.new(
      :id,
      :album_type,
      :name,
      :label,
      :external_ids,
      :external_urls,
      :total_tracks,
      :release_date,
      :available_markets,
      keyword_init: true
    ) do
      def tracks
        []
      end

      def as_json(*)
        {
          'id' => id,
          'album_type' => album_type,
          'name' => name,
          'label' => label,
          'external_ids' => external_ids,
          'external_urls' => external_urls,
          'total_tracks' => total_tracks,
          'release_date' => release_date,
          'artists' => [],
          'available_markets' => available_markets
        }
      end
    end

    test 'creates Spotify album by Apple Music JAN' do
      jan_code = "spotify-jan-search-#{SecureRandom.hex(4)}"
      album = create_album_with_apple_music(jan_code:)
      api_album = spotify_api_album(jan_code:)
      queries = []

      spotify_album_client = Class.new do
        define_singleton_method(:search) do |query, **_options|
          queries << query
          [api_album]
        end
      end

      target_scope = ::Album.where(id: album.id).includes(:apple_music_album)
      with_rspotify_backend do
        with_missing_spotify_album_scope(target_scope) do
          stub_const(RSpotify, :Album, spotify_album_client) do
            assert_difference -> { SpotifyAlbum.unscoped.count }, 1 do
              @result = SpotifyClient::Album.fetch_missing_albums_by_apple_music_jan(sleep_interval: 0)
            end
          end
        end
      end

      spotify_album = SpotifyAlbum.unscoped.find_by!(album:)

      assert_equal "spotify-#{jan_code}", spotify_album.spotify_id
      assert_equal 'Spotify JAN Album', spotify_album.name
      assert_equal "upc:#{jan_code}", queries.last
      assert_equal 1, @result[:created]
      assert_equal 0, @result[:errors]
    end

    test 'searches albums with Spotify search limit and paginates by returned size' do
      calls = []
      processed_ids = []
      first_page = Array.new(SpotifyClient::Album::SEARCH_LIMIT) { |index| spotify_api_album(jan_code: "search-page-1-#{index}") }
      second_page = [spotify_api_album(jan_code: 'search-page-2-0')]

      spotify_album_client = Class.new do
        define_singleton_method(:search) do |_query, **options|
          calls << options
          options.fetch(:offset).zero? ? first_page : second_page
        end
      end

      with_rspotify_backend do
        with_spotify_album_processor(->(album) { processed_ids << album.id }) do
          stub_const(RSpotify, :Album, spotify_album_client) do
            SpotifyClient::Album.search_and_save_albums('label:test year:2026', 2026)
          end
        end
      end

      assert_equal(
        [SpotifyClient::Album::SEARCH_LIMIT, SpotifyClient::Album::SEARCH_LIMIT],
        calls.map { |call| call.fetch(:limit) }
      )
      assert_equal(
        [0, SpotifyClient::Album::SEARCH_LIMIT],
        calls.map { |call| call.fetch(:offset) }
      )
      assert_equal first_page.concat(second_page).map(&:id), processed_ids
    end

    test 'reports progress while fetching Touhou albums by year' do
      updates = []
      searched_years = []

      with_spotify_album_searcher(->(_keyword, year) { searched_years << year }) do
        SpotifyClient::Album.fetch_touhou_albums(
          progress_callback: ->(**attrs) { updates << attrs }
        )
      end

      years = (2000..Time.zone.today.year).to_a

      assert_equal years, searched_years
      assert_equal(
        { current: 0, total: years.size, message: 'Spotify アルバムを取得しています', reset: true },
        updates.first
      )
      assert_equal years.size, updates.last.fetch(:current)
      assert_equal years.size, updates.last.fetch(:total)
      assert_includes updates.last.fetch(:message), "#{Time.zone.today.year}年"
    end

    test 'does not search albums that already have inactive Spotify albums' do
      jan_code = "spotify-jan-skip-#{SecureRandom.hex(4)}"
      album = create_album_with_apple_music(jan_code:)
      SpotifyAlbum.create!(
        album:,
        spotify_id: "inactive-#{jan_code}",
        album_type: 'album',
        name: 'Inactive Spotify Album',
        label: ::Album::TOUHOU_MUSIC_LABEL,
        active: false,
        payload: { 'available_markets' => ['JP'] }
      )

      scope = SpotifyClient::Album.send(:missing_spotify_albums_with_apple_music)

      assert_empty scope.where(id: album.id)
    end

    # 検索結果の簡易オブジェクトには label / external_ids が無いため、そのまま保存すると
    # レーベル判定と UPC 照合が壊れる。新規アルバムはフル取得してから保存すること。
    test 'native backend fetches the full album for search results that lack label' do
      jan_code = "native-full-#{SecureRandom.hex(4)}"
      spotify_id = "album-#{jan_code}"
      album_api, album_calls = fake_album_api(
        find_results: { spotify_id => full_album_body(spotify_id:, jan_code:, tracks: [simplified_track_body(1)]) },
        search_page: page_body([simplified_album_body(spotify_id)]),
        tracks_pages: [page_body([simplified_track_body(1)])]
      )
      track_api, track_calls = fake_track_api({ 'track-1' => full_track_body(1) })

      with_native_backend do
        stub_const(SpotifyApi, :Album, album_api) do
          stub_const(SpotifyApi, :Track, track_api) do
            assert_difference -> { SpotifyAlbum.unscoped.count }, 1 do
              SpotifyClient::Album.search_and_save_albums('label:test year:2026', 2026)
            end
          end
        end
      end

      spotify_album = SpotifyAlbum.unscoped.find_by!(spotify_id:)

      assert_equal ::Album::TOUHOU_MUSIC_LABEL, spotify_album.label
      assert_equal jan_code, spotify_album.album.jan_code
      assert_equal [spotify_id], called_ids(album_calls[:find])
      assert_equal %w[track-1], called_ids(track_calls)
      assert_equal ['ISRC0001'], spotify_album.spotify_tracks.map(&:isrc)
    end

    # クォータ回帰テスト: 既存の SpotifyAlbum は API を叩き直さず再利用する。
    test 'native backend does not refetch an album that is already saved' do
      spotify_album = create_spotify_album(total_tracks: 1)
      album_api, album_calls = fake_album_api(
        tracks_pages: [page_body([simplified_track_body(1)])]
      )
      track_api, _track_calls = fake_track_api({ 'track-1' => full_track_body(1) })

      with_native_backend do
        stub_const(SpotifyApi, :Album, album_api) do
          stub_const(SpotifyApi, :Track, track_api) do
            SpotifyClient::Album.process_album(SpotifyApi::Response.build(simplified_album_body(spotify_album.spotify_id)))
          end
        end
      end

      assert_empty album_calls[:find]
      assert_equal [spotify_album.spotify_id], called_ids(album_calls[:tracks])
      assert_equal ['ISRC0001'], spotify_album.spotify_tracks.reload.map(&:isrc)
    end

    # クォータ回帰テスト: 既に保存済みのトラックはフル取得し直さない。
    # 取得し直して上書きすると、簡易オブジェクトの payload で ISRC が失われる。
    test 'native backend fetches only tracks that are not saved yet' do
      spotify_album = create_spotify_album(total_tracks: 2)
      create_spotify_track(spotify_album, 1)
      album_api, _album_calls = fake_album_api(
        tracks_pages: [page_body([simplified_track_body(1), simplified_track_body(2)])]
      )
      track_api, track_calls = fake_track_api({ 'track-2' => full_track_body(2) })

      with_native_backend do
        stub_const(SpotifyApi, :Album, album_api) do
          stub_const(SpotifyApi, :Track, track_api) do
            assert_difference -> { SpotifyTrack.unscoped.count }, 1 do
              SpotifyClient::Album.process_album(SpotifyApi::Response.build(simplified_album_body(spotify_album.spotify_id)))
            end
          end
        end
      end

      assert_equal %w[track-2], called_ids(track_calls)
    end

    test 'native backend pages through albums with more than one page of tracks' do
      jan_code = "native-paging-#{SecureRandom.hex(4)}"
      spotify_id = "album-#{jan_code}"
      first_page_tracks = (1..SpotifyClient::Album::LIMIT).map { |number| simplified_track_body(number) }
      album_body = full_album_body(
        spotify_id:,
        jan_code:,
        total_tracks: SpotifyClient::Album::LIMIT + 1,
        tracks: first_page_tracks,
        tracks_next: 'https://api.spotify.com/v1/albums/next'
      )
      album_api, album_calls = fake_album_api(
        find_results: { spotify_id => album_body },
        tracks_pages: [
          page_body(first_page_tracks, next_url: 'https://api.spotify.com/v1/albums/next'),
          page_body([simplified_track_body(SpotifyClient::Album::LIMIT + 1)])
        ]
      )
      track_api, _track_calls = fake_track_api(
        (1..(SpotifyClient::Album::LIMIT + 1)).index_with { |number| full_track_body(number) }
                                             .transform_keys { |number| "track-#{number}" }
      )

      with_native_backend do
        stub_const(SpotifyApi, :Album, album_api) do
          stub_const(SpotifyApi, :Track, track_api) do
            SpotifyClient::Album.fetch_and_process_album(spotify_id)
          end
        end
      end

      spotify_album = SpotifyAlbum.unscoped.find_by!(spotify_id:)

      assert_equal SpotifyClient::Album::LIMIT + 1, spotify_album.spotify_tracks.count
      assert_equal(
        [
          { id: spotify_id, options: { limit: SpotifyClient::Album::LIMIT, offset: 0 } },
          { id: spotify_id, options: { limit: SpotifyClient::Album::LIMIT, offset: SpotifyClient::Album::LIMIT } }
        ],
        album_calls[:tracks]
      )
    end

    # GET /albums/{id} に tracks が埋め込まれていても、relinking (下記の回帰テスト参照)
    # で canonical でない ID になり得るため信用せず、必ず専用の /albums/{id}/tracks を呼ぶ。
    test 'native backend always calls the tracks endpoint even when tracks are embedded' do
      jan_code = "native-embedded-#{SecureRandom.hex(4)}"
      spotify_id = "album-#{jan_code}"
      album_api, album_calls = fake_album_api(
        find_results: { spotify_id => full_album_body(spotify_id:, jan_code:, tracks: [simplified_track_body(1)]) },
        tracks_pages: [page_body([simplified_track_body(1)])]
      )
      track_api, _track_calls = fake_track_api({ 'track-1' => full_track_body(1) })

      with_native_backend do
        stub_const(SpotifyApi, :Album, album_api) do
          stub_const(SpotifyApi, :Track, track_api) do
            SpotifyClient::Album.fetch_and_process_album(spotify_id)
          end
        end
      end

      assert_equal [spotify_id], called_ids(album_calls[:tracks])
      assert_equal 1, SpotifyAlbum.unscoped.find_by!(spotify_id:).spotify_tracks.count
    end

    # クォータ回帰テストではない: 既存の SpotifyAlbum でも GET /albums/{id} に埋め込まれた
    # tracks は信用せず、/albums/{id}/tracks を必ず呼び直す。
    test 'native backend always calls the tracks endpoint for an album that is already saved' do
      spotify_album = create_spotify_album(total_tracks: 1)
      spotify_id = spotify_album.spotify_id
      album_api, album_calls = fake_album_api(
        find_results: {
          spotify_id => full_album_body(spotify_id:, jan_code: spotify_album.album.jan_code, tracks: [simplified_track_body(1)])
        },
        tracks_pages: [page_body([simplified_track_body(1)])]
      )
      track_api, _track_calls = fake_track_api({ 'track-1' => full_track_body(1) })

      with_native_backend do
        stub_const(SpotifyApi, :Album, album_api) do
          stub_const(SpotifyApi, :Track, track_api) do
            SpotifyClient::Album.fetch_and_process_album(spotify_id)
          end
        end
      end

      assert_equal [spotify_id], called_ids(album_calls[:tracks])
      assert_equal ['ISRC0001'], spotify_album.spotify_tracks.reload.map(&:isrc)
    end

    # 回帰テスト: GET /albums/{id} に埋め込まれた tracks は track relinking により
    # canonical ではない ID (linked_from 付き) で返ることがある。埋め込みを再利用すると
    # 既存の canonical ID と食い違い、同じ曲が重複保存される。
    test 'native backend saves the canonical track id even when the embedded tracks are relinked' do
      jan_code = "native-relinked-#{SecureRandom.hex(4)}"
      spotify_id = "album-#{jan_code}"
      relinked_track = simplified_track_body(1).merge(
        'id' => 'relinked-track-1',
        'linked_from' => { 'id' => 'track-1' }
      )
      album_api, album_calls = fake_album_api(
        find_results: { spotify_id => full_album_body(spotify_id:, jan_code:, tracks: [relinked_track]) },
        tracks_pages: [page_body([simplified_track_body(1)])]
      )
      track_api, track_calls = fake_track_api({ 'track-1' => full_track_body(1) })

      with_native_backend do
        stub_const(SpotifyApi, :Album, album_api) do
          stub_const(SpotifyApi, :Track, track_api) do
            SpotifyClient::Album.fetch_and_process_album(spotify_id)
          end
        end
      end

      spotify_album = SpotifyAlbum.unscoped.find_by!(spotify_id:)

      assert_equal 1, album_calls[:tracks].size
      assert_equal %w[track-1], called_ids(track_calls)
      assert_equal ['track-1'], spotify_album.spotify_tracks.map(&:spotify_id)
    end

    # next はあるのに items が空という異常応答でページングが止まることを保証する。
    test 'native backend stops paging tracks when a page has no items' do
      jan_code = "native-empty-page-#{SecureRandom.hex(4)}"
      spotify_id = "album-#{jan_code}"
      first_page_tracks = (1..SpotifyClient::Album::LIMIT).map { |number| simplified_track_body(number) }
      album_api, album_calls = fake_album_api(
        find_results: {
          spotify_id => full_album_body(
            spotify_id:,
            jan_code:,
            total_tracks: SpotifyClient::Album::LIMIT + 1,
            tracks: first_page_tracks,
            tracks_next: 'https://api.spotify.com/v1/albums/next'
          )
        },
        tracks_pages: [
          page_body(first_page_tracks, next_url: 'https://api.spotify.com/v1/albums/next'),
          page_body([], next_url: 'https://api.spotify.com/v1/albums/next2')
        ]
      )
      track_api, _track_calls = fake_track_api(
        (1..SpotifyClient::Album::LIMIT).index_with { |number| full_track_body(number) }
                                        .transform_keys { |number| "track-#{number}" }
      )

      with_native_backend do
        stub_const(SpotifyApi, :Album, album_api) do
          stub_const(SpotifyApi, :Track, track_api) do
            SpotifyClient::Album.fetch_and_process_album(spotify_id)
          end
        end
      end

      assert_equal 2, album_calls[:tracks].size
      assert_equal SpotifyClient::Album::LIMIT, SpotifyAlbum.unscoped.find_by!(spotify_id:).spotify_tracks.count
    end

    # 検索側も next はあるのに items が空という異常応答で止まる。
    test 'native backend stops searching albums when a page has no items' do
      calls = []
      search_pages = [
        page_body([], next_url: 'https://api.spotify.com/v1/search/next'),
        page_body([], next_url: nil)
      ]

      album_api = Class.new do
        define_singleton_method(:search) do |query, **options|
          calls << { query:, options: }
          SpotifyApi::Page.build(search_pages.shift)
        end
      end

      with_native_backend do
        stub_const(SpotifyApi, :Album, album_api) do
          SpotifyClient::Album.search_and_save_albums('label:test year:2026', 2026)
        end
      end

      assert_equal 1, calls.size
    end

    # #559 回帰テスト: market を渡すと available_markets が返らなくなり、
    # 配信中のアルバムが「配信終了」と誤判定される。
    test 'native backend never passes market to the album endpoints' do
      jan_code = "native-market-#{SecureRandom.hex(4)}"
      spotify_id = "album-#{jan_code}"
      album_api, album_calls = fake_album_api(
        find_results: { spotify_id => full_album_body(spotify_id:, jan_code:, tracks: []) },
        search_page: page_body([simplified_album_body(spotify_id)])
      )

      with_native_backend do
        stub_const(SpotifyApi, :Album, album_api) do
          SpotifyClient::Album.search_and_save_albums('label:test year:2026', 2026)
        end
      end

      assert_equal [{}], called_options(album_calls[:find])
      album_calls[:search].each do |call|
        assert_not call.fetch(:options).key?(:market)
      end
    end

    # upc: 検索の結果も簡易オブジェクトなので、候補をフル取得してから UPC を照合する。
    test 'native backend matches JAN codes against fully fetched candidates' do
      jan_code = "native-jan-#{SecureRandom.hex(4)}"
      album = create_album_with_apple_music(jan_code:)
      album_api, album_calls = fake_album_api(
        find_results: {
          'album-other' => full_album_body(spotify_id: 'album-other', jan_code: 'other-jan', total_tracks: 0, tracks: []),
          'album-match' => full_album_body(spotify_id: 'album-match', jan_code:, total_tracks: 0, tracks: [])
        },
        search_page: page_body([simplified_album_body('album-other'), simplified_album_body('album-match')])
      )

      target_scope = ::Album.where(id: album.id).includes(:apple_music_album)
      with_native_backend do
        with_missing_spotify_album_scope(target_scope) do
          stub_const(SpotifyApi, :Album, album_api) do
            assert_difference -> { SpotifyAlbum.unscoped.count }, 1 do
              @result = SpotifyClient::Album.fetch_missing_albums_by_apple_music_jan(sleep_interval: 0)
            end
          end
        end
      end

      assert_equal 1, @result[:created]
      assert_equal 0, @result[:errors]
      assert_equal "upc:#{jan_code}", album_calls[:search].last.fetch(:query)
      assert_equal 'album-match', SpotifyAlbum.unscoped.find_by!(album:).spotify_id
    end

    # #559 回帰テスト: Spotify は GET /albums/{id} から available_markets を段階的に削除しており、
    # 空で返ってきても配信終了を意味しない。そのまま payload を上書きすると jp_available? が
    # 反転し、preferred_active_album が正しいアルバムを非アクティブにしてしまう。
    test 'native backend keeps existing available_markets when the fetched album has none' do
      spotify_album = create_spotify_album(total_tracks: 1, payload: { 'available_markets' => %w[JP US] })
      spotify_id = spotify_album.spotify_id
      degraded_body = full_album_body(spotify_id:, jan_code: spotify_album.album.jan_code, tracks: []).except('available_markets')
      album_api, _album_calls = fake_album_api(find_results: { spotify_id => degraded_body })

      with_native_backend do
        stub_const(SpotifyApi, :Album, album_api) do
          SpotifyClient::Album.update_albums([spotify_album])
        end
      end

      assert_equal %w[JP US], spotify_album.reload.payload['available_markets']
      assert_equal 'Full Album', spotify_album.payload['name']
      assert_predicate spotify_album, :jp_available?
    end

    # 旧経路でも同じガードが効くことを保証する（#563 で rspotify を削除するまでの間の回帰防止）。
    test 'rspotify backend keeps existing available_markets when the fetched album has none' do
      spotify_album = create_spotify_album(total_tracks: 1, payload: { 'available_markets' => %w[JP US] })
      api_album = SpotifyApiAlbum.new(
        id: spotify_album.spotify_id,
        album_type: 'album',
        name: 'Updated Spotify Album',
        label: ::Album::TOUHOU_MUSIC_LABEL,
        external_ids: { 'upc' => spotify_album.album.jan_code },
        external_urls: { 'spotify' => 'https://open.spotify.com/album/test' },
        total_tracks: 1,
        release_date: '2026-01-01',
        available_markets: []
      )

      spotify_album_client = Class.new do
        define_singleton_method(:find) { |_ids| [api_album] }
      end

      with_rspotify_backend do
        stub_const(RSpotify, :Album, spotify_album_client) do
          SpotifyClient::Album.update_albums([spotify_album])
        end
      end

      assert_equal %w[JP US], spotify_album.reload.payload['available_markets']
      assert_equal 'Updated Spotify Album', spotify_album.payload['name']
      assert_predicate spotify_album, :jp_available?
    end

    private

    def create_album_with_apple_music(jan_code:)
      ::Album.create!(jan_code:).tap do |album|
        AppleMusicAlbum.create!(
          album:,
          apple_music_id: "apple-#{jan_code}",
          name: 'Apple Music Album',
          label: ::Album::TOUHOU_MUSIC_LABEL,
          url: 'https://music.apple.com/test',
          release_date: Date.new(2026, 1, 1),
          total_tracks: 0,
          payload: {}
        )
      end
    end

    def create_spotify_album(total_tracks:, payload: { 'available_markets' => ['JP'] })
      jan_code = "native-existing-#{SecureRandom.hex(4)}"
      album = ::Album.create!(jan_code:)
      SpotifyAlbum.create!(
        album:,
        spotify_id: "album-#{jan_code}",
        album_type: 'album',
        name: 'Existing Spotify Album',
        label: ::Album::TOUHOU_MUSIC_LABEL,
        total_tracks:,
        payload:
      )
    end

    def create_spotify_track(spotify_album, number)
      track = ::Track.create!(jan_code: spotify_album.album.jan_code, isrc: format('ISRC%04d', number))
      spotify_album.album.tracks << track
      SpotifyTrack.create!(
        album: spotify_album.album,
        spotify_album:,
        track:,
        spotify_id: "track-#{number}",
        name: "Track #{number}",
        label: spotify_album.label,
        disc_number: 1,
        track_number: number,
        duration_ms: 1000,
        payload: {}
      )
    end

    def spotify_api_album(jan_code:, available_markets: ['JP'])
      SpotifyApiAlbum.new(
        id: "spotify-#{jan_code}",
        album_type: 'album',
        name: 'Spotify JAN Album',
        label: ::Album::TOUHOU_MUSIC_LABEL,
        external_ids: { 'upc' => jan_code },
        external_urls: { 'spotify' => 'https://open.spotify.com/album/test' },
        total_tracks: 0,
        release_date: '2026-01-01',
        available_markets:
      )
    end

    # GET /search が返す簡易オブジェクト。label と external_ids を持たない。
    def simplified_album_body(spotify_id)
      {
        'id' => spotify_id,
        'album_type' => 'album',
        'name' => 'Simplified Album',
        'external_urls' => { 'spotify' => "https://open.spotify.com/album/#{spotify_id}" },
        'total_tracks' => 1,
        'release_date' => '2026-01-01',
        'artists' => []
      }
    end

    def full_album_body(spotify_id:, jan_code:, tracks:, total_tracks: 1, tracks_next: nil)
      {
        'id' => spotify_id,
        'album_type' => 'album',
        'name' => 'Full Album',
        'label' => ::Album::TOUHOU_MUSIC_LABEL,
        'external_ids' => { 'upc' => jan_code },
        'external_urls' => { 'spotify' => "https://open.spotify.com/album/#{spotify_id}" },
        'total_tracks' => total_tracks,
        'release_date' => '2026-01-01',
        'artists' => [],
        'available_markets' => ['JP'],
        'tracks' => page_body(tracks, next_url: tracks_next)
      }
    end

    # GET /albums/{id}/tracks が返す簡易オブジェクト。external_ids (ISRC) を持たない。
    def simplified_track_body(number)
      {
        'id' => "track-#{number}",
        'name' => "Track #{number}",
        'disc_number' => 1,
        'track_number' => number,
        'duration_ms' => 1000,
        'external_urls' => { 'spotify' => "https://open.spotify.com/track/track-#{number}" }
      }
    end

    def full_track_body(number)
      simplified_track_body(number).merge('external_ids' => { 'isrc' => format('ISRC%04d', number) })
    end

    def page_body(items, next_url: nil)
      {
        'items' => items,
        'total' => items.size,
        'limit' => SpotifyClient::Album::LIMIT,
        'offset' => 0,
        'next' => next_url
      }
    end

    def called_ids(calls)
      calls.map { |call| call.fetch(:id) }
    end

    def called_options(calls)
      calls.map { |call| call.fetch(:options) }
    end

    def fake_album_api(find_results: {}, search_page: nil, tracks_pages: [])
      calls = { find: [], search: [], tracks: [] }
      remaining_tracks_pages = tracks_pages.dup

      klass = Class.new do
        define_singleton_method(:find) do |id, **options|
          calls[:find] << { id:, options: }
          SpotifyApi::Response.build(find_results.fetch(id))
        end

        define_singleton_method(:find_many) do |ids, **options|
          ids.map { |id| find(id, **options) }
        end

        define_singleton_method(:search) do |query, **options|
          calls[:search] << { query:, options: }
          SpotifyApi::Page.build(search_page)
        end

        define_singleton_method(:tracks) do |id, **options|
          calls[:tracks] << { id:, options: }
          SpotifyApi::Page.build(remaining_tracks_pages.shift)
        end
      end

      [klass, calls]
    end

    def fake_track_api(find_results)
      calls = []

      klass = Class.new do
        define_singleton_method(:find) do |id, **options|
          calls << { id:, options: }
          SpotifyApi::Response.build(find_results.fetch(id))
        end
      end

      [klass, calls]
    end

    def with_native_backend(&)
      with_native_client_enabled(true, &)
    end

    def with_rspotify_backend(&)
      with_native_client_enabled(false, &)
    end

    def with_native_client_enabled(enabled)
      original = SpotifyApi.config.native_client_enabled
      SpotifyApi.config.native_client_enabled = enabled
      yield
    ensure
      SpotifyApi.config.native_client_enabled = original
    end

    def with_missing_spotify_album_scope(scope)
      singleton_class = SpotifyClient::Album.singleton_class
      original_method = SpotifyClient::Album.method(:missing_spotify_albums_with_apple_music)

      singleton_class.define_method(:missing_spotify_albums_with_apple_music) { scope }
      singleton_class.send(:private, :missing_spotify_albums_with_apple_music)
      yield
    ensure
      singleton_class.define_method(:missing_spotify_albums_with_apple_music, original_method)
      singleton_class.send(:private, :missing_spotify_albums_with_apple_music)
    end

    # search_and_save_albums はバックエンド内の process_album を呼ぶため、
    # 差し替え対象もバックエンド側になる。
    def with_spotify_album_processor(processor)
      backend = SpotifyClient::Album::RspotifyBackend
      singleton_class = backend.singleton_class
      original_method = backend.method(:process_album)

      singleton_class.define_method(:process_album) { |album| processor.call(album) }
      yield
    ensure
      singleton_class.define_method(:process_album, original_method)
    end

    def with_spotify_album_searcher(searcher)
      singleton_class = SpotifyClient::Album.singleton_class
      original_method = SpotifyClient::Album.method(:search_and_save_albums)

      singleton_class.define_method(:search_and_save_albums) { |keyword, year| searcher.call(keyword, year) }
      yield
    ensure
      singleton_class.define_method(:search_and_save_albums, original_method)
    end
  end
end
