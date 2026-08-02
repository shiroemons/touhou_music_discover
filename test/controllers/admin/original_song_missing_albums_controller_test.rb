# frozen_string_literal: true

require 'test_helper'

module Admin
  class OriginalSongMissingAlbumsControllerTest < ActionDispatch::IntegrationTest
    test 'lists albums that include tracks missing original songs' do
      missing_album = create_album(jan_code: '9777777780101', circle_name: 'Missing Circle', album_name: 'Missing Album')
      missing_track = create_track(album: missing_album, isrc: 'JPABC2780101')
      create_track(album: missing_album, isrc: 'JPABC2780102')

      linked_album = create_album(jan_code: '9777777780102', circle_name: 'Linked Circle', album_name: 'Linked Album')
      linked_track = create_track(album: linked_album, isrc: 'JPABC2780103')
      linked_track.original_songs << create_original_song(code: 'MISSING-ALBUM-LINKED-001', title: 'Linked Original Song')

      get admin_original_song_missing_albums_url

      assert_response :success
      assert_select 'h1', '原曲紐づけが必要なアルバム'
      assert_select 'td', text: 'Missing Circle'
      assert_select 'td', text: 'Missing Album'
      assert_select 'td', text: '2'
      assert_select 'td', { text: 'Linked Album', count: 0 }
      assert_select 'a[href=?]', admin_track_original_song_assignments_path(q: missing_album.jan_code, view: 'albums'), text: '紐づけ'
      assert_select 'textarea[data-admin-clipboard-target=?]', 'source', text: "Missing Circle\tMissing Album"
      assert_not_includes response.body, missing_track.isrc
    end

    test 'filters missing albums and copies matching circle and album columns' do
      matching_album = create_album(jan_code: '9777777780111', circle_name: 'Filter Circle', album_name: 'Filter Album')
      other_album = create_album(jan_code: '9777777780112', circle_name: 'Other Circle', album_name: 'Other Album')
      create_track(album: matching_album, isrc: 'JPABC2780111')
      create_track(album: other_album, isrc: 'JPABC2780112')

      get admin_original_song_missing_albums_url, params: { q: 'Filter' }

      assert_response :success
      assert_select 'td', text: 'Filter Album'
      assert_select 'td', { text: 'Other Album', count: 0 }
      assert_select 'textarea[data-admin-clipboard-target=?]', 'source', text: "Filter Circle\tFilter Album"
    end

    private

    def create_album(jan_code:, circle_name:, album_name:)
      album = Album.create!(jan_code:)
      album.circles << Circle.create!(name: circle_name)
      SpotifyAlbum.create!(
        album:,
        spotify_id: "#{jan_code}-spotify",
        album_type: 'album',
        name: album_name,
        label: Album::TOUHOU_MUSIC_LABEL,
        active: true,
        payload: { 'available_markets' => ['JP'] }
      )
      album
    end

    def create_track(album:, isrc:)
      Track.create!(album:, isrc:)
    end

    def create_original_song(code:, title:)
      original = Original.find_or_create_by!(code: "#{code}-ORIGINAL") do |record|
        record.title = "#{title} Original"
        record.short_title = "#{title} Original"
        record.original_type = 'other'
        record.series_order = 900.0
      end

      OriginalSong.create!(
        code:,
        original:,
        title:,
        composer: 'ZUN',
        track_number: 1
      )
    end
  end
end
