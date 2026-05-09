# frozen_string_literal: true

require 'test_helper'

module Admin
  class ResourcesControllerTest < ActionDispatch::IntegrationTest
    test 'lists a registered resource' do
      get admin_resources_url('albums')

      assert_response :success
      assert_select 'h1', 'アルバム'
      assert_select 'th', 'JANコード'
      assert_select 'th', '東方'
      assert_equal(
        ['JANコード', 'サークル', 'Spotifyアルバム名', 'Apple Musicアルバム名', 'YouTube Musicアルバム名', 'LINE MUSICアルバム名', '東方', '操作'],
        css_select('thead th').map { it.text.squish }
      )
      assert_select '.admin-filter-field label', text: '未配信'
      assert_select '.admin-filter-field label', text: '原曲'
      assert_select 'select[name=?][onchange=?]', 'filters[not_delivered]', 'this.form.requestSubmit()'
      assert_select 'select[name=?][onchange=?]', 'filters[tracks_original_songs]', 'this.form.requestSubmit()'
      assert_select 'select[name=?] option', 'filters[not_delivered]', text: 'Apple Music未配信'
      assert_select 'select[name=?] option', 'filters[tracks_original_songs]', text: '未設定の楽曲あり'
      assert_select 'a[href=?]', admin_resource_action_path('albums', 'change_touhou_flag'), text: '東方フラグを変更'
      assert_select '.admin-list-toolbar'
      assert_select '.admin-record-count', text: /表示中/
      assert_select 'table'
    end

    test 'lists youtube music and line music album names on albums index' do
      album = Album.create!(jan_code: '9777777777766')
      YtmusicAlbum.create!(
        album:,
        browse_id: 'ytmusic-admin-album',
        name: 'Admin YouTube Music Album',
        payload: {}
      )
      LineMusicAlbum.create!(
        album:,
        line_music_id: 'line-music-admin-album',
        name: 'Admin LINE MUSIC Album',
        payload: {}
      )

      get admin_resources_url('albums'), params: { q: album.jan_code }

      assert_response :success
      assert_select 'th', text: 'YouTube Musicアルバム名'
      assert_select 'th', text: 'LINE MUSICアルバム名'
      assert_select 'tr.admin-clickable-row[data-controller=?]', 'admin-clickable-row'
      assert_select 'tr.admin-clickable-row[data-admin-clickable-row-href-value=?]', admin_resource_path('albums', album)
      assert_select 'td', text: 'Admin YouTube Music Album'
      assert_select 'td', text: 'Admin LINE MUSIC Album'
    end

    test 'shows streaming service top links on album index pages' do
      get admin_resources_url('albums')

      assert_response :success
      assert_select '.admin-page-actions .admin-external-link-menu summary', text: '外部リンク'
      assert_select '.admin-page-actions .admin-external-link-menu a', count: 4
      assert_select '.admin-page-actions .admin-external-link-menu a[href=?]', 'https://open.spotify.com/', text: 'Spotify'
      assert_select '.admin-page-actions .admin-external-link-menu a[href=?]', 'https://music.apple.com/jp/browse', text: 'Apple Music'
      assert_select '.admin-page-actions .admin-external-link-menu a[href=?]', 'https://music.youtube.com/', text: 'YouTube Music'
      assert_select '.admin-page-actions .admin-external-link-menu a[href=?]', 'https://music.line.me/webapp', text: 'LINE MUSIC'

      get admin_resources_url('spotify_albums')

      assert_response :success
      assert_select '.admin-page-actions .admin-external-link-menu a', count: 1
      assert_select '.admin-page-actions .admin-external-link-menu a[href=?]', 'https://open.spotify.com/', text: 'Spotify'
    end

    test 'links streaming album names to each service resource with service artwork' do
      album = Album.create!(jan_code: '9777777777767')
      spotify_album = SpotifyAlbum.create!(
        album:,
        spotify_id: 'spotify-admin-service-artwork',
        album_type: 'album',
        name: 'Admin Spotify Artwork Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        payload: { 'images' => [{ 'url' => 'https://example.test/spotify-cover.jpg' }] }
      )
      line_music_album = LineMusicAlbum.create!(
        album:,
        line_music_id: 'line-music-admin-service-artwork',
        name: 'Admin LINE Artwork Album',
        payload: { 'image_url' => 'https://example.test/line-cover.jpg' }
      )

      get admin_resources_url('albums'), params: { q: album.jan_code }

      assert_response :success
      assert_select 'a[href=?].admin-index-record-link .admin-value-label', admin_resource_path('spotify_albums', spotify_album), text: spotify_album.name
      assert_select 'a[href=?].admin-index-record-link img[src=?][alt=?]', admin_resource_path('spotify_albums', spotify_album), 'https://example.test/spotify-cover.jpg', spotify_album.name
      assert_select 'a[href=?].admin-index-record-link .admin-value-label', admin_resource_path('line_music_albums', line_music_album), text: line_music_album.name
      assert_select 'a[href=?].admin-index-record-link img[src=?][alt=?]', admin_resource_path('line_music_albums', line_music_album), 'https://example.test/line-cover.jpg', line_music_album.name
      assert_select 'a[href=?].admin-index-record-link img[src=?]', admin_resource_path('line_music_albums', line_music_album), 'https://example.test/spotify-cover.jpg', count: 0
    end

    test 'filters albums with tracks missing original songs' do
      missing_album = Album.create!(jan_code: '9777777777931')
      linked_album = Album.create!(jan_code: '9777777777932')
      Track.create!(album: missing_album, isrc: 'JPABC260531')
      linked_track = Track.create!(album: linked_album, isrc: 'JPABC260532')
      original = Original.create!(
        code: 'ADMIN-ALBUM-ORIGINAL',
        title: 'Admin Album Original',
        short_title: 'Album Admin',
        original_type: 'other',
        series_order: 1.0
      )
      original_song = OriginalSong.create!(
        code: 'ADMIN-ALBUM-ORIGINAL-001',
        original:,
        title: 'Admin Album Original Song',
        composer: 'ZUN',
        track_number: 1
      )
      TracksOriginalSong.create!(track: linked_track, original_song:)

      get admin_resources_url('albums'), params: { q: '977777777793', filters: { tracks_original_songs: 'missing' } }

      assert_response :success
      assert_select 'select[name=?] option[selected]', 'filters[tracks_original_songs]', text: '未設定の楽曲あり'
      assert_select '.admin-filter-chip', text: /原曲/
      assert_select '.admin-filter-chip', text: /未設定の楽曲あり/
      assert_select '.admin-filter-chip', text: /検索語/
      assert_select '.admin-filter-chip', text: /977777777793/
      assert_select 'td', text: missing_album.jan_code
      assert_select 'td', { text: linked_album.jan_code, count: 0 }
    end

    test 'shows relations on detail page' do
      album = Album.create!(jan_code: '9777777777777')
      Track.create!(album:, isrc: 'JPABC260003')

      get admin_resource_url('albums', album)

      assert_response :success
      assert_select 'h2', '概要'
      assert_select 'h2', 'すべての項目'
      assert_select '.admin-record-overview'
      assert_select 'h2', '関連'
      assert_select '.admin-relation-header', /楽曲/
      assert_select 'a[href=?]', admin_resource_path('tracks', album.tracks.first), text: '詳細'
    end

    test 'hides join relation and shows original title on original song relation' do
      album = Album.create!(jan_code: '9777777777778')
      track = Track.create!(album:, isrc: 'JPABC260005')
      original = Original.create!(
        code: 'ADMIN-RELATION-ORIGINAL',
        title: 'Admin Relation Original',
        short_title: 'Relation Original',
        original_type: 'other',
        series_order: 1.0
      )
      original_song = OriginalSong.create!(
        code: 'ADMIN-RELATION-ORIGINAL-001',
        original:,
        title: 'Admin Relation Original Song',
        composer: 'ZUN',
        track_number: 1
      )
      TracksOriginalSong.create!(track:, original_song:)

      get admin_resource_url('tracks', track)

      assert_response :success
      assert_select '.admin-relation-header', /原曲/
      assert_select '.admin-relation-header', { text: /楽曲・原曲/, count: 0 }
      assert_select '.admin-relation-record-label', text: 'Admin Relation Original Song'
      assert_select '.admin-relation-record-meta', text: '原作: Admin Relation Original / トラック 1'
    end

    test 'lists tracks by jan code and shows album name on detail' do
      older_album = Album.create!(jan_code: '9777777777901')
      newer_album = Album.create!(jan_code: '9777777777902')
      older_track = Track.create!(album: older_album, isrc: 'JPABC260501')
      newer_track = Track.create!(album: newer_album, isrc: 'JPABC260502')
      SpotifyAlbum.create!(
        album: newer_album,
        spotify_id: 'spotify-admin-track-detail-album',
        album_type: 'album',
        name: 'Admin Track Detail Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        payload: {}
      )

      get admin_resources_url('tracks'), params: { q: '977777777790' }

      assert_response :success
      assert_select '.admin-filter-field label', text: '未取得'
      assert_select '.admin-filter-field label', text: '原曲数'
      assert_select 'select[name=?][onchange=?]', 'filters[missing_streaming_track]', 'this.form.requestSubmit()'
      assert_select 'select[name=?][onchange=?]', 'filters[original_songs_count]', 'this.form.requestSubmit()'
      assert_select 'select[name=?] option', 'filters[original_songs_count]', text: '0曲'
      assert_select 'th', text: '配信取得'
      row_jan_codes = css_select('tbody tr').map { |row| row.css('td')[3].text.squish }
      assert_equal [newer_track.jan_code, older_track.jan_code], row_jan_codes
      assert_select 'a.admin-streaming-status-badge', text: 'Spotify未取得'
      assert_select 'a[href=?].admin-streaming-status-badge', admin_resources_path('tracks', filters: { missing_streaming_track: :apple_music }), text: 'Apple Music未取得'

      get admin_resource_url('tracks', newer_track)

      assert_response :success
      assert_select '.admin-detail-table th', text: 'アルバム名'
      assert_select '.admin-detail-table th', text: '配信取得'
      assert_select '.admin-detail-table td', text: 'Admin Track Detail Album'
    end

    test 'filters tracks by missing streaming service' do
      missing_album = Album.create!(jan_code: '9777777777911')
      delivered_album = Album.create!(jan_code: '9777777777912')
      missing_track = Track.create!(album: missing_album, isrc: 'JPABC260511')
      delivered_track = Track.create!(album: delivered_album, isrc: 'JPABC260512')
      delivered_spotify_album = SpotifyAlbum.create!(
        album: delivered_album,
        spotify_id: 'spotify-admin-track-filter-delivered-album',
        album_type: 'album',
        name: 'Delivered Track Filter Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        payload: {}
      )
      SpotifyTrack.create!(
        album: delivered_album,
        track: delivered_track,
        spotify_album: delivered_spotify_album,
        spotify_id: 'spotify-admin-track-filter-delivered',
        name: 'Delivered Track Filter Song',
        label: Album::TOUHOU_MUSIC_LABEL,
        disc_number: 1,
        track_number: 1,
        duration_ms: 180_000,
        payload: {}
      )

      get admin_resources_url('tracks'), params: { q: '977777777791', filters: { missing_streaming_track: 'spotify' } }

      assert_response :success
      assert_select 'td', text: missing_track.isrc
      assert_select 'td', { text: delivered_track.isrc, count: 0 }
    end

    test 'filters tracks by original songs count' do
      missing_album = Album.create!(jan_code: '9777777777921')
      linked_album = Album.create!(jan_code: '9777777777922')
      missing_track = Track.create!(album: missing_album, isrc: 'JPABC260521')
      linked_track = Track.create!(album: linked_album, isrc: 'JPABC260522')
      original = Original.create!(
        code: 'ADMIN-ORIGINAL',
        title: 'Admin Original',
        short_title: 'Admin',
        original_type: 'other',
        series_order: 1.0
      )
      original_song = OriginalSong.create!(
        code: 'ADMIN-ORIGINAL-001',
        original:,
        title: 'Admin Original Song',
        composer: 'ZUN',
        track_number: 1
      )
      TracksOriginalSong.create!(track: linked_track, original_song:)

      get admin_resources_url('tracks'), params: { q: '977777777792', filters: { original_songs_count: 'none' } }

      assert_response :success
      assert_select 'select[name=?] option[selected]', 'filters[original_songs_count]', text: '0曲'
      assert_select 'td', text: missing_track.isrc
      assert_select 'td', { text: linked_track.isrc, count: 0 }

      get admin_resources_url('tracks'), params: { q: '977777777792', filters: { original_songs_count: 'present' } }

      assert_response :success
      assert_select 'td', text: linked_track.isrc
      assert_select 'td', { text: missing_track.isrc, count: 0 }
    end

    test 'shows all related records with track numbers' do
      album = Album.create!(jan_code: '9777777777799')
      spotify_album = SpotifyAlbum.create!(
        album:,
        spotify_id: 'spotify-admin-relations',
        album_type: 'album',
        name: 'Admin Relations Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        payload: {}
      )
      11.times do |index|
        track = Track.create!(album:, isrc: format('JPABC2601%02d', index))
        SpotifyTrack.create!(
          album:,
          track:,
          spotify_album:,
          spotify_id: "spotify-admin-relation-track-#{index}",
          name: "Relation Track #{index + 1}",
          label: Album::TOUHOU_MUSIC_LABEL,
          disc_number: 1,
          track_number: index + 1,
          duration_ms: 180_000,
          payload: {}
        )
      end

      get admin_resource_url('spotify_albums', spotify_album)

      assert_response :success
      assert_select '.admin-relation-header', /Spotify楽曲/
      assert_select '.admin-relation-record-label', text: 'Relation Track 11'
      assert_select '.admin-relation-record-meta', text: 'ディスク 1 / トラック 11'
      assert_select '.admin-hint', 0
    end

    test 'shows external service links at the top of streaming album detail pages' do
      album = Album.create!(jan_code: '9777777777801')
      spotify_album = SpotifyAlbum.create!(
        album:,
        spotify_id: 'spotify-admin-external-link',
        album_type: 'album',
        name: 'Admin Spotify External Link',
        label: Album::TOUHOU_MUSIC_LABEL,
        url: 'https://open.spotify.com/album/admin-external-link',
        payload: {}
      )
      apple_music_album = AppleMusicAlbum.create!(
        album:,
        apple_music_id: 'apple-admin-external-link',
        name: 'Admin Apple External Link',
        label: Album::TOUHOU_MUSIC_LABEL,
        url: 'https://music.apple.com/jp/album/admin-external-link',
        payload: {}
      )
      ytmusic_album = YtmusicAlbum.create!(
        album:,
        browse_id: 'ytmusic-admin-external-link',
        name: 'Admin YouTube Music External Link',
        playlist_url: 'https://music.youtube.com/playlist?list=admin-external-link',
        payload: {}
      )
      line_music_album = LineMusicAlbum.create!(
        album:,
        line_music_id: 'line-admin-external-link',
        name: 'Admin LINE External Link',
        url: 'https://music.line.me/webapp/album/line-admin-external-link',
        payload: {}
      )

      assert_streaming_album_external_link('spotify_albums', spotify_album, 'Spotifyで開く', spotify_album.url)
      assert_streaming_album_external_link('apple_music_albums', apple_music_album, 'Apple Musicで開く', apple_music_album.url)
      assert_streaming_album_external_link('ytmusic_albums', ytmusic_album, 'YouTube Musicで開く', ytmusic_album.playlist_url)
      assert_streaming_album_external_link('line_music_albums', line_music_album, 'LINE MUSICで開く', line_music_album.url)
    end

    test 'shows artwork and readable association labels instead of raw foreign keys' do
      circle = Circle.create!(name: 'Admin Circle')
      album = Album.create!(jan_code: '9888888888888')
      album.circles << circle
      track = Track.create!(album:, isrc: 'JPABC260004')
      spotify_album = SpotifyAlbum.create!(
        album:,
        spotify_id: 'spotify-admin-artwork',
        album_type: 'album',
        name: 'Admin Artwork Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        payload: { 'images' => [{ 'url' => 'https://example.test/cover.jpg' }] }
      )
      spotify_track = SpotifyTrack.create!(
        album:,
        track:,
        spotify_album:,
        spotify_id: 'spotify-admin-track',
        name: 'Admin Track',
        label: Album::TOUHOU_MUSIC_LABEL,
        disc_number: 1,
        track_number: 1,
        duration_ms: 180_000,
        payload: {}
      )

      get admin_resources_url('spotify_tracks')

      assert_response :success
      assert_equal(
        ['名前', 'サークル', 'JANコード', '楽曲', 'Spotifyアルバム', 'ディスク番号', 'トラック番号', 'Spotify ID', '操作'],
        css_select('thead th').map { it.text.squish }
      )
      assert_select 'a[href=?].admin-index-record-link .admin-value-label', admin_resource_path('spotify_tracks', spotify_track), text: 'Admin Track'
      assert_select '.admin-value-with-thumb img[src=?][alt=?]', 'https://example.test/cover.jpg', 'Admin Track'
      assert_select '.admin-reference-card img', 0
      assert_select 'td', text: 'Admin Circle'
      assert_select 'a[href=?].admin-reference-card .admin-reference-label', admin_resource_path('albums', album), text: album.jan_code
      assert_select 'a[href=?].admin-reference-card .admin-reference-label', admin_resource_path('tracks', track), text: 'Admin Track'
      assert_select 'a[href=?].admin-reference-card .admin-reference-meta', admin_resource_path('tracks', track), text: /#{track.isrc}/
      assert_select 'a[href=?].admin-reference-card .admin-reference-label', admin_resource_path('spotify_albums', spotify_album), text: spotify_album.name

      get admin_resource_url('spotify_tracks', spotify_track)

      assert_response :success
      assert_select '.admin-detail-table th', text: 'JANコード'
      assert_select '.admin-detail-table th', text: '楽曲'
      assert_select '.admin-detail-table th', text: 'Spotifyアルバム'
      assert_select '.admin-detail-table th', { text: 'アルバムID', count: 0 }
      assert_select '.admin-detail-table th', { text: '楽曲ID', count: 0 }
      assert_select '.admin-detail-table th', { text: 'SpotifyアルバムID', count: 0 }
    end

    test 'lists spotify track audio features resource with fetch action' do
      album = Album.create!(jan_code: '9777777777941')
      track = Track.create!(album:, isrc: 'JPABC260541')
      spotify_album = SpotifyAlbum.create!(
        album:,
        spotify_id: 'spotify-admin-audio-feature-album',
        album_type: 'album',
        name: 'Audio Feature Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        payload: {}
      )
      spotify_track = SpotifyTrack.create!(
        album:,
        track:,
        spotify_album:,
        spotify_id: 'spotify-admin-audio-feature-track',
        name: 'Audio Feature Track',
        label: Album::TOUHOU_MUSIC_LABEL,
        disc_number: 1,
        track_number: 1,
        duration_ms: 180_000,
        payload: {}
      )
      SpotifyTrackAudioFeature.create!(
        track:,
        spotify_track:,
        spotify_id: spotify_track.spotify_id,
        acousticness: 0.1,
        danceability: 0.2,
        duration_ms: 180_000,
        energy: 0.3,
        instrumentalness: 0.4,
        key: 1,
        liveness: 0.5,
        loudness: -5.0,
        mode: 1,
        speechiness: 0.6,
        tempo: 128.0,
        time_signature: 4,
        valence: 0.7,
        payload: {}
      )

      get admin_resources_url('spotify_track_audio_features')

      assert_response :success
      assert_select 'h1', 'Spotify音響特徴'
      assert_select 'th', text: 'Spotify楽曲'
      assert_select 'th', text: 'テンポ'
      assert_select 'td', text: spotify_track.spotify_id
      assert_select 'a[href=?]', admin_resource_action_path('spotify_track_audio_features', 'fetch_spotify_audio_features'), text: 'Spotify オーディオ特性を取得'
    end

    test 'orders spotify track audio features like spotify tracks' do
      older_feature = create_spotify_track_audio_feature(
        jan_code: '9777777777951',
        isrc: 'JPABC260551',
        spotify_id: 'spotify-admin-audio-feature-order-older'
      )
      newer_second_feature = create_spotify_track_audio_feature(
        jan_code: '9777777777952',
        isrc: 'JPABC260552',
        spotify_id: 'spotify-admin-audio-feature-order-newer-second',
        track_number: 2
      )
      newer_first_feature = create_spotify_track_audio_feature(
        jan_code: '9777777777952',
        isrc: 'JPABC260553',
        spotify_id: 'spotify-admin-audio-feature-order-newer-first',
        track_number: 1
      )

      get admin_resources_url('spotify_track_audio_features'), params: { q: '977777777795' }

      assert_response :success
      row_spotify_ids = css_select('tbody tr').map { |row| row.css('td').first.text.squish }
      assert_equal(
        [newer_first_feature.spotify_id, newer_second_feature.spotify_id, older_feature.spotify_id],
        row_spotify_ids
      )
    end

    test 'searches and filters spotify track audio features by related fields and musical characteristics' do
      matching_feature = create_spotify_track_audio_feature(
        jan_code: '9777777777961',
        isrc: 'JPABC260561',
        spotify_id: 'spotify-admin-audio-feature-filter-match',
        spotify_album_name: 'Searchable Audio Feature Album',
        spotify_track_name: 'Searchable Audio Feature Track',
        tempo: 150.0,
        energy: 0.8,
        mode: 1
      )
      other_feature = create_spotify_track_audio_feature(
        jan_code: '9777777777962',
        isrc: 'JPABC260562',
        spotify_id: 'spotify-admin-audio-feature-filter-other',
        spotify_album_name: 'Other Audio Feature Album',
        spotify_track_name: 'Other Audio Feature Track',
        tempo: 80.0,
        energy: 0.2,
        mode: 0
      )

      get admin_resources_url('spotify_track_audio_features'), params: {
        q: 'Searchable Audio Feature Track',
        filters: {
          audio_feature_profile: 'high_energy',
          audio_tempo: 'fast',
          audio_mode: 'major'
        }
      }

      assert_response :success
      assert_select '.admin-filter-field label', text: '特徴'
      assert_select '.admin-filter-field label', text: 'テンポ'
      assert_select '.admin-filter-field label', text: '調性'
      assert_select 'select[name=?] option[selected]', 'filters[audio_feature_profile]', text: '高エネルギー'
      assert_select 'select[name=?] option[selected]', 'filters[audio_tempo]', text: '速い（140 BPM以上）'
      assert_select 'select[name=?] option[selected]', 'filters[audio_mode]', text: 'メジャー'
      assert_select 'td', text: matching_feature.spotify_id
      assert_select 'td', { text: other_feature.spotify_id, count: 0 }

      get admin_resources_url('spotify_track_audio_features'), params: { q: matching_feature.track.isrc }

      assert_response :success
      assert_select 'td', text: matching_feature.spotify_id
      assert_select 'td', { text: other_feature.spotify_id, count: 0 }
    end

    test 'filters spotify track audio features by loudness duration time signature and data quality' do
      matching_feature = create_spotify_track_audio_feature(
        jan_code: '9777777777971',
        isrc: 'JPABC260571',
        spotify_id: 'spotify-admin-audio-feature-advanced-filter-match',
        duration_ms: 420_000,
        loudness: -5.0,
        time_signature: 5,
        analysis_url: ''
      )
      other_feature = create_spotify_track_audio_feature(
        jan_code: '9777777777972',
        isrc: 'JPABC260572',
        spotify_id: 'spotify-admin-audio-feature-advanced-filter-other',
        duration_ms: 90_000,
        loudness: -25.0,
        time_signature: 4,
        analysis_url: 'https://api.spotify.com/v1/audio-analysis/other'
      )

      get admin_resources_url('spotify_track_audio_features'), params: {
        filters: {
          audio_loudness: 'loud',
          audio_duration: 'long',
          audio_time_signature: 'irregular',
          audio_data_quality: 'missing_analysis_url'
        }
      }

      assert_response :success
      assert_select '.admin-filter-field label', text: '音量'
      assert_select '.admin-filter-field label', text: '長さ'
      assert_select '.admin-filter-field label', text: '拍子'
      assert_select '.admin-filter-field label', text: 'データ品質'
      assert_select 'select[name=?] option[selected]', 'filters[audio_loudness]', text: '大きめ（-8 dB以上）'
      assert_select 'select[name=?] option[selected]', 'filters[audio_duration]', text: '長い（6分以上）'
      assert_select 'select[name=?] option[selected]', 'filters[audio_time_signature]', text: '変拍子（5拍子以上）'
      assert_select 'select[name=?] option[selected]', 'filters[audio_data_quality]', text: '解析URLなし'
      assert_select 'td', text: matching_feature.spotify_id
      assert_select 'td', { text: other_feature.spotify_id, count: 0 }
    end

    test 'filters records separately from keyword search' do
      missing_album = Album.create!(jan_code: '9777777777781')
      delivered_album = Album.create!(jan_code: '9777777777782')
      AppleMusicAlbum.create!(
        album: delivered_album,
        apple_music_id: 'apple-music-delivered-admin',
        name: 'Delivered Admin Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        payload: {}
      )

      get admin_resources_url('albums'), params: { q: '977777777778', filters: { not_delivered: 'apple_music' } }

      assert_response :success
      assert_select 'input[name=?][value=?]', 'q', '977777777778'
      assert_select 'select[name=?]', 'filters[not_delivered]'
      assert_select 'td', text: missing_album.jan_code
      assert_select 'td', { text: delivered_album.jan_code, count: 0 }
    end

    test 'matches Avo spotify album display filter' do
      active_album = Album.create!(jan_code: '9777777777811', is_touhou: true)
      inactive_album = Album.create!(jan_code: '9777777777812')
      non_touhou_album = Album.create!(jan_code: '9777777777813', is_touhou: false)
      active_spotify_album = SpotifyAlbum.create!(
        album: active_album,
        spotify_id: 'spotify-admin-display-active',
        album_type: 'album',
        name: 'Active Display Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        active: true,
        payload: {}
      )
      inactive_spotify_album = SpotifyAlbum.create!(
        album: inactive_album,
        spotify_id: 'spotify-admin-display-inactive',
        album_type: 'album',
        name: 'Inactive Display Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        active: false,
        payload: {}
      )
      non_touhou_spotify_album = SpotifyAlbum.create!(
        album: non_touhou_album,
        spotify_id: 'spotify-admin-display-non-touhou',
        album_type: 'album',
        name: 'Non Touhou Display Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        active: true,
        payload: {}
      )

      get admin_resources_url('spotify_albums')

      assert_response :success
      assert_select '.admin-filter-field label', text: '表示'
      assert_select '.admin-filter-field label', text: '東方'
      assert_select 'select[name=?][onchange=?]', 'filters[display]', 'this.form.requestSubmit()'
      assert_select 'select[name=?][onchange=?]', 'filters[touhou]', 'this.form.requestSubmit()'
      assert_select 'select[name=?] option[selected]', 'filters[display]', text: 'アクティブのみ'
      assert_select 'td', text: active_spotify_album.name
      assert_select 'td', text: non_touhou_spotify_album.name
      assert_select 'td', { text: inactive_spotify_album.name, count: 0 }

      get admin_resources_url('spotify_albums'), params: { filters: { display: 'inactive' } }

      assert_response :success
      assert_select 'td', text: inactive_spotify_album.name
      assert_select 'td', { text: active_spotify_album.name, count: 0 }

      get admin_resources_url('spotify_albums'), params: { filters: { display: 'active', touhou: 'true' } }

      assert_response :success
      assert_select 'td', text: active_spotify_album.name
      assert_select 'td', { text: non_touhou_spotify_album.name, count: 0 }
    end

    test 'shows streaming album track status with quick action' do
      album = Album.create!(jan_code: '9777777777831')
      spotify_album = SpotifyAlbum.create!(
        album:,
        spotify_id: 'spotify-admin-track-status',
        album_type: 'album',
        name: 'Track Status Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        active: true,
        total_tracks: 2,
        payload: {}
      )
      track = Track.create!(album:, isrc: 'JPABC260301')
      SpotifyTrack.create!(
        album:,
        track:,
        spotify_album:,
        spotify_id: 'spotify-admin-track-status-track',
        name: 'Track Status Song',
        label: Album::TOUHOU_MUSIC_LABEL,
        disc_number: 1,
        track_number: 1,
        duration_ms: 180_000,
        payload: {}
      )

      get admin_resources_url('spotify_albums'), params: { q: spotify_album.spotify_id }

      assert_response :success
      assert_select 'th', text: '楽曲取得'
      assert_select '.admin-track-status-count', text: '1 / 2'
      assert_select '.admin-track-status .badge', text: '不足'
      assert_select 'a[href=?].admin-track-status-action', admin_resource_action_path('spotify_albums', 'fetch_spotify_album'), text: '取得へ'
    end

    test 'filters streaming albums by track status' do
      incomplete_album = Album.create!(jan_code: '9777777777841')
      complete_album = Album.create!(jan_code: '9777777777842')
      missing_album = Album.create!(jan_code: '9777777777843')
      incomplete_spotify_album = SpotifyAlbum.create!(
        album: incomplete_album,
        spotify_id: 'spotify-admin-track-status-incomplete',
        album_type: 'album',
        name: 'Incomplete Track Status Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        active: true,
        total_tracks: 2,
        payload: {}
      )
      complete_spotify_album = SpotifyAlbum.create!(
        album: complete_album,
        spotify_id: 'spotify-admin-track-status-complete',
        album_type: 'album',
        name: 'Complete Track Status Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        active: true,
        total_tracks: 1,
        payload: {}
      )
      missing_spotify_album = SpotifyAlbum.create!(
        album: missing_album,
        spotify_id: 'spotify-admin-track-status-missing',
        album_type: 'album',
        name: 'Missing Track Status Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        active: true,
        total_tracks: 1,
        payload: {}
      )
      incomplete_track = Track.create!(album: incomplete_album, isrc: 'JPABC260401')
      complete_track = Track.create!(album: complete_album, isrc: 'JPABC260402')
      SpotifyTrack.create!(
        album: incomplete_album,
        track: incomplete_track,
        spotify_album: incomplete_spotify_album,
        spotify_id: 'spotify-admin-track-status-incomplete-track',
        name: 'Incomplete Track Status Song',
        label: Album::TOUHOU_MUSIC_LABEL,
        disc_number: 1,
        track_number: 1,
        duration_ms: 180_000,
        payload: {}
      )
      SpotifyTrack.create!(
        album: complete_album,
        track: complete_track,
        spotify_album: complete_spotify_album,
        spotify_id: 'spotify-admin-track-status-complete-track',
        name: 'Complete Track Status Song',
        label: Album::TOUHOU_MUSIC_LABEL,
        disc_number: 1,
        track_number: 1,
        duration_ms: 180_000,
        payload: {}
      )

      get admin_resources_url('spotify_albums'), params: { filters: { display: 'active', track_status: 'incomplete' } }

      assert_response :success
      assert_select '.admin-filter-field label', text: '楽曲取得'
      assert_select 'select[name=?][onchange=?]', 'filters[track_status]', 'this.form.requestSubmit()'
      assert_select 'td', text: incomplete_spotify_album.name
      assert_select 'td', { text: complete_spotify_album.name, count: 0 }
      assert_select 'td', { text: missing_spotify_album.name, count: 0 }
    end

    test 'shows readable admin pagination' do
      (Admin::Resource::DEFAULT_ITEMS + 1).times do |index|
        Circle.create!(name: "Pagination Circle #{index}")
      end

      get admin_resources_url('circles'), params: { scroll: 'pagination' }

      assert_response :success
      assert_select '.admin-view-mode-label', text: '表示方式'
      assert_select 'a.admin-view-mode-link.is-active', text: 'ページ送り'
      assert_select 'a.admin-view-mode-link[href$=?]', admin_resources_path('circles'), text: '無限スクロール'
      assert_select 'nav.admin-pagination[aria-label=?]', 'ページ送り'
      assert_select '.admin-pagination-summary', /件中/
      assert_select '.admin-pagination-link.is-current', text: '1'
      assert_select 'a.admin-pagination-link[aria-label=?]', '2ページへ移動'
    end

    test 'supports infinite scroll mode on admin index' do
      (Admin::Resource::DEFAULT_ITEMS + 1).times do |index|
        Circle.create!(name: "Infinite Scroll Circle #{index}")
      end

      get admin_resources_url('circles')

      assert_response :success
      assert_select 'input[type=hidden][name=?][value=?]', 'scroll', 'infinite'
      assert_select 'a.admin-view-mode-link.is-active', text: '無限スクロール'
      assert_select '.admin-table-panel[data-controller=?]', 'admin-infinite-scroll'
      assert_select '.admin-table-panel[data-admin-infinite-scroll-next-url-value*=?]', 'scroll=infinite'
      assert_select '.admin-table-panel[data-admin-infinite-scroll-next-url-value*=?]', 'page=2'
      assert_select '.admin-infinite-scroll-status', text: '下までスクロールすると追加で読み込みます。'
      assert_select '.admin-infinite-scroll-sentinel'
      assert_select 'nav.admin-pagination', 0
    end

    test 'filters streaming tracks by touhou flag' do
      touhou_album = Album.create!(jan_code: '9777777777821', is_touhou: true)
      non_touhou_album = Album.create!(jan_code: '9777777777822', is_touhou: false)
      touhou_track = Track.create!(album: touhou_album, isrc: 'JPABC260201', is_touhou: true)
      non_touhou_track = Track.create!(album: non_touhou_album, isrc: 'JPABC260202', is_touhou: false)
      touhou_spotify_album = SpotifyAlbum.create!(
        album: touhou_album,
        spotify_id: 'spotify-admin-track-filter-album-touhou',
        album_type: 'album',
        name: 'Touhou Track Filter Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        payload: {}
      )
      non_touhou_spotify_album = SpotifyAlbum.create!(
        album: non_touhou_album,
        spotify_id: 'spotify-admin-track-filter-album-non-touhou',
        album_type: 'album',
        name: 'Non Touhou Track Filter Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        payload: {}
      )
      touhou_spotify_track = SpotifyTrack.create!(
        album: touhou_album,
        track: touhou_track,
        spotify_album: touhou_spotify_album,
        spotify_id: 'spotify-admin-track-filter-touhou',
        name: 'Touhou Filter Track',
        label: Album::TOUHOU_MUSIC_LABEL,
        disc_number: 1,
        track_number: 1,
        duration_ms: 180_000,
        payload: {}
      )
      non_touhou_spotify_track = SpotifyTrack.create!(
        album: non_touhou_album,
        track: non_touhou_track,
        spotify_album: non_touhou_spotify_album,
        spotify_id: 'spotify-admin-track-filter-non-touhou',
        name: 'Non Touhou Filter Track',
        label: Album::TOUHOU_MUSIC_LABEL,
        disc_number: 1,
        track_number: 1,
        duration_ms: 180_000,
        payload: {}
      )

      get admin_resources_url('spotify_tracks'), params: { filters: { touhou: 'true' } }

      assert_response :success
      assert_select '.admin-filter-field label', text: '東方'
      assert_select 'select[name=?]', 'filters[touhou]'
      assert_select 'td', text: touhou_spotify_track.name
      assert_select 'td', { text: non_touhou_spotify_track.name, count: 0 }
    end

    test 'creates updates and destroys a circle' do
      assert_difference('Circle.count', 1) do
        post admin_resources_url('circles'), params: { record: { name: 'New Admin Circle' } }
      end

      circle = Circle.find_by!(name: 'New Admin Circle')
      assert_redirected_to admin_resource_path('circles', circle)

      patch admin_resource_url('circles', circle), params: { record: { name: 'Updated Admin Circle' } }
      assert_redirected_to admin_resource_path('circles', circle)
      assert_equal 'Updated Admin Circle', circle.reload.name

      assert_difference('Circle.count', -1) do
        delete admin_resource_url('circles', circle)
      end
      assert_redirected_to admin_resources_path('circles')
    end

    test 'rejects invalid json payload' do
      album = Album.create!(jan_code: '9999999999999')
      spotify_album = SpotifyAlbum.create!(
        album:,
        spotify_id: 'spotify-admin-test',
        album_type: 'album',
        name: 'Admin Test Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        payload: {}
      )

      patch admin_resource_url('spotify_albums', spotify_album), params: { record: { payload: '{invalid' } }

      assert_response :unprocessable_content
      assert_select '.alert-error', /JSON/
    end

    test 'formats payload as pretty json on detail page' do
      album = Album.create!(jan_code: '9888888888899')
      spotify_album = SpotifyAlbum.create!(
        album:,
        spotify_id: 'spotify-admin-json',
        album_type: 'album',
        name: 'Admin JSON Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        payload: { 'images' => [{ 'url' => 'https://example.test/json-cover.jpg' }] }
      )

      get admin_resource_url('spotify_albums', spotify_album)

      assert_response :success
      assert_select 'pre.admin-json-block', /"images": \[/
      assert_select 'pre.admin-json-block', %r{"url": "https://example.test/json-cover.jpg"}
    end

    test 'keeps avo mounted' do
      assert_equal '/avo', Avo.configuration.root_path
    end

    test 'does not route unknown admin resource names to generic resources controller' do
      get '/admin/import-legacy'

      assert_response :not_found
    end

    test 'shows action confirmation without running the action' do
      get admin_resource_action_url('albums', 'change_touhou_flag')

      assert_response :success
      assert_select 'h1', '東方フラグを変更'
      assert_select '.alert-warning', /外部API通信/
      assert_select '.admin-action-summary', text: /実行内容/
      assert_select '.admin-action-summary strong', '東方フラグを変更'
      assert_select '.admin-action-summary p', /原曲紐づけ済み/
      assert_select '.admin-action-summary li', /進捗を確認できます/
      assert_select '.admin-action-summary li', /未検出/
      assert_select 'form[data-controller=?][data-action=?]', 'admin-action-confirm', 'submit->admin-action-confirm#submit'
      assert_select '.modal[data-admin-action-confirm-target=?]', 'modal'
      assert_select '#admin-action-confirm-title', text: 'アクションを実行しますか？'
      assert_select '.admin-action-confirm-description', /原曲紐づけ済み/
      assert_select 'button[type=submit]', text: '実行'
      assert_select 'button[type=submit][data-turbo-confirm]', count: 0
    end

    test 'shows ytmusic jan action form without browser confirm dependency' do
      get admin_resource_action_url('ytmusic_albums', 'process_ytmusic_jan_to_album_browse_ids')

      assert_response :success
      assert_select 'h1', 'JAN_TO_ALBUM_BROWSE_IDS を処理'
      assert_select 'form[action=?][method=post]', admin_resource_action_path('ytmusic_albums', 'process_ytmusic_jan_to_album_browse_ids')
      assert_select 'form[data-controller=?][data-action=?]', 'admin-action-confirm', 'submit->admin-action-confirm#submit'
      assert_select '.alert-warning', /外部API通信/
      assert_select '.modal[data-admin-action-confirm-target=?]', 'modal'
      assert_select 'button[type=submit]', text: '実行'
      assert_select 'button[type=submit][data-turbo-confirm]', count: 0
    end

    private

    def create_spotify_track_audio_feature(
      jan_code:,
      isrc:,
      spotify_id:,
      **overrides
    )
      attributes = spotify_track_audio_feature_attributes(overrides)
      album = Album.find_or_create_by!(jan_code:)
      track = Track.create!(album:, isrc:)
      spotify_album = SpotifyAlbum.find_by(album:) || SpotifyAlbum.create!(
        album:,
        spotify_id: "spotify-admin-audio-feature-album-#{jan_code}",
        album_type: 'album',
        name: attributes.fetch(:spotify_album_name),
        label: Album::TOUHOU_MUSIC_LABEL,
        payload: {}
      )
      spotify_track = SpotifyTrack.create!(
        album:,
        track:,
        spotify_album:,
        spotify_id:,
        name: attributes.fetch(:spotify_track_name),
        label: Album::TOUHOU_MUSIC_LABEL,
        disc_number: attributes.fetch(:disc_number),
        track_number: attributes.fetch(:track_number),
        duration_ms: attributes.fetch(:duration_ms),
        payload: {}
      )
      SpotifyTrackAudioFeature.create!(
        track:,
        spotify_track:,
        spotify_id:,
        acousticness: 0.1,
        danceability: 0.6,
        duration_ms: attributes.fetch(:duration_ms),
        energy: attributes.fetch(:energy),
        instrumentalness: 0.1,
        key: 1,
        liveness: 0.1,
        loudness: attributes.fetch(:loudness),
        mode: attributes.fetch(:mode),
        speechiness: 0.1,
        tempo: attributes.fetch(:tempo),
        time_signature: attributes.fetch(:time_signature),
        valence: 0.5,
        analysis_url: attributes.fetch(:analysis_url),
        payload: attributes.fetch(:payload)
      )
    end

    def assert_streaming_album_external_link(resource_key, record, label, url)
      get admin_resource_url(resource_key, record)

      assert_response :success
      assert_select '.admin-external-link-bar', text: /外部リンク/
      assert_select '.admin-external-link-bar a[href=?][target=?][rel=?]', url, '_blank', 'noopener noreferrer', text: label
    end

    def spotify_track_audio_feature_attributes(overrides)
      {
        spotify_album_name: 'Admin Audio Feature Album',
        spotify_track_name: 'Admin Audio Feature Track',
        disc_number: 1,
        track_number: 1,
        duration_ms: 180_000,
        tempo: 128.0,
        energy: 0.5,
        mode: 1,
        loudness: -5.0,
        time_signature: 4,
        analysis_url: '',
        payload: {}
      }.merge(overrides)
    end
  end
end
