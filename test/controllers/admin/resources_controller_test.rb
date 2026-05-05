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
        ['Spotifyアルバム名', 'Apple Musicアルバム名', 'サークル', 'JANコード', '東方', '操作'],
        css_select('thead th').map { it.text.squish }
      )
      assert_select '.admin-filter-field label', text: '未配信'
      assert_select 'select[name=?][onchange=?]', 'filters[not_delivered]', 'this.form.requestSubmit()'
      assert_select 'select[name=?] option', 'filters[not_delivered]', text: 'Apple Music未配信'
      assert_select 'a[href=?]', admin_resource_action_path('albums', 'change_touhou_flag'), text: '東方フラグを変更'
      assert_select 'table'
    end

    test 'shows relations on detail page' do
      album = Album.create!(jan_code: '9777777777777')
      Track.create!(album:, isrc: 'JPABC260003')

      get admin_resource_url('albums', album)

      assert_response :success
      assert_select 'h2', '関連'
      assert_select '.admin-relation-header', /楽曲/
      assert_select 'a[href=?]', admin_resource_path('tracks', album.tracks.first), text: '詳細'
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
      active_album = Album.create!(jan_code: '9777777777811')
      inactive_album = Album.create!(jan_code: '9777777777812')
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

      get admin_resources_url('spotify_albums')

      assert_response :success
      assert_select '.admin-filter-field label', text: '表示'
      assert_select 'select[name=?][onchange=?]', 'filters[display]', 'this.form.requestSubmit()'
      assert_select 'select[name=?] option[selected]', 'filters[display]', text: 'アクティブのみ'
      assert_select 'td', text: active_spotify_album.name
      assert_select 'td', { text: inactive_spotify_album.name, count: 0 }

      get admin_resources_url('spotify_albums'), params: { filters: { display: 'inactive' } }

      assert_response :success
      assert_select 'td', text: inactive_spotify_album.name
      assert_select 'td', { text: active_spotify_album.name, count: 0 }
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
      assert_select '.alert-danger', /JSON/
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
      assert_select 'pre.admin-json-block', /"url": "https:\/\/example.test\/json-cover.jpg"/
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
      assert_select 'button[type=submit]', text: '実行'
    end
  end
end
