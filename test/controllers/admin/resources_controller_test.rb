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
      SpotifyTrack.create!(
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
        ['名前', 'サークル', 'アルバムID', '楽曲ID', 'SpotifyアルバムID', 'ディスク番号', 'トラック番号', 'Spotify ID', '操作'],
        css_select('thead th').map { it.text.squish }
      )
      assert_select '.admin-value-with-thumb img[src=?][alt=?]', 'https://example.test/cover.jpg', 'Admin Track'
      assert_select '.admin-reference-card img', 0
      assert_select 'td', text: 'Admin Circle'
      assert_select 'a[href=?].admin-reference-card .admin-reference-label', admin_resource_path('albums', album), text: album.jan_code
      assert_select 'a[href=?].admin-reference-card .admin-reference-label', admin_resource_path('tracks', track), text: 'Admin Track'
      assert_select 'a[href=?].admin-reference-card .admin-reference-meta', admin_resource_path('tracks', track), text: /#{track.isrc}/
      assert_select 'a[href=?].admin-reference-card .admin-reference-label', admin_resource_path('spotify_albums', spotify_album), text: spotify_album.name
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
