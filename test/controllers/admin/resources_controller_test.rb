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
      assert_select 'a[href=?]', admin_resource_action_path('albums', 'change_touhou_flag'), text: '東方フラグを変更'
      assert_select 'table'
    end

    test 'shows relations on detail page' do
      album = Album.create!(jan_code: '9777777777777')
      Track.create!(album:, isrc: 'JPABC260003')

      get admin_resource_url('albums', album)

      assert_response :success
      assert_select 'h2', '関連'
      assert_select '.card-header', /楽曲/
      assert_select 'a[href=?]', admin_resource_path('tracks', album.tracks.first), text: '詳細'
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
      assert_select 'input[type=submit][value=?]', '実行'
    end
  end
end
