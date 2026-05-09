# frozen_string_literal: true

require 'test_helper'

module Admin
  class ActionTest < ActiveSupport::TestCase
    test 'resolves non Avo admin action classes' do
      Admin::Resource.all.each do |resource|
        resource.actions.each do |action|
          assert_operator action.action_class, :<, Admin::Actions::BaseAction
          assert_not_equal 'Avo::BaseAction', action.action_class.superclass.name
        end
      end
    end

    test 'runs touhou flag action without depending on Avo action implementation' do
      album = Album.create!(jan_code: '4777777777777')
      track = Track.create!(album:, isrc: 'JPABC260601')

      action = Admin::Resource.find!('albums').action_for!('change_touhou_flag')
      result = action.run

      assert_predicate result, :success?
      assert_predicate track.reload, :is_touhou?
      assert_predicate album.reload, :is_touhou?
    end

    test 'fetches only missing Apple Music tracks by ISRC' do
      album = create_album('4777777777801')
      missing_track = create_track(album, 'JPABC260701')
      present_track = create_track(album, 'JPABC260702')
      apple_music_album = AppleMusicAlbum.create!(
        album:,
        apple_music_id: 'apple-album-1',
        name: 'Apple Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        total_tracks: 2
      )
      AppleMusicTrack.create!(
        album:,
        track: present_track,
        apple_music_album:,
        apple_music_id: 'apple-track-1',
        name: 'Present Apple Track',
        label: Album::TOUHOU_MUSIC_LABEL
      )
      fetched_isrcs = []
      result = nil
      fetch_by_isrc = lambda do |isrc|
        fetched_isrcs << isrc
        AppleMusicTrack.create!(
          album:,
          track: missing_track,
          apple_music_album:,
          apple_music_id: 'apple-track-2',
          name: 'Fetched Apple Track',
          label: Album::TOUHOU_MUSIC_LABEL
        )
      end

      with_singleton_method(AppleMusicClient::Track, :fetch_tracks_by_isrc, fetch_by_isrc) do
        result = Admin::Resource.find!('apple_music_tracks').action_for!('fetch_missing_apple_music_tracks').run

        assert_predicate result, :success?
      end

      assert_equal [missing_track.isrc], fetched_isrcs
      assert_includes result.message, '- 取得: 1件'
      assert_includes result.message, '- 未検出: 0件'
      assert_includes result.message, '- 取得一覧:'
      assert_includes result.message, '  - JPABC260701 - Fetched Apple Track'
      assert_includes result.message, 'Fetched Apple Track'
    end

    test 'fetches only LINE MUSIC albums that have missing tracks' do
      target_album = create_album('4777777777811')
      create_track(target_album, 'JPABC260711')
      LineMusicAlbum.create!(
        album: target_album,
        line_music_id: 'line-album-1',
        name: 'Line Album',
        total_tracks: 1
      )
      spotify_album = SpotifyAlbum.create!(
        album: target_album,
        spotify_id: 'spotify-album-line',
        album_type: 'album',
        name: 'Source Spotify Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        total_tracks: 1
      )
      SpotifyTrack.create!(
        album: target_album,
        track: target_album.tracks.first,
        spotify_album:,
        spotify_id: 'spotify-track-line',
        name: 'Line Missing Source Track',
        label: Album::TOUHOU_MUSIC_LABEL
      )
      skipped_album = create_album('4777777777812')
      create_track(skipped_album, 'JPABC260712')
      processed_jan_codes = []
      result = nil

      with_singleton_method(LineMusicTrack, :process_album, ->(album) { processed_jan_codes << album.jan_code }) do
        result = Admin::Resource.find!('line_music_tracks').action_for!('fetch_missing_line_music_tracks').run

        assert_predicate result, :success?
      end

      assert_equal [target_album.jan_code], processed_jan_codes
      assert_includes result.message, '- 未検出: 1アルバム'
      assert_includes result.message, '- 未検出一覧:'
      assert_includes result.message, '  - Line Album'
      assert_includes result.message, '    - JPABC260711 - Line Missing Source Track'
      assert_includes result.message, 'Line Album'
      assert_includes result.message, 'Line Missing Source Track'
    end

    test 'fetches only YouTube Music albums that have missing tracks' do
      target_album = create_album('4777777777821')
      create_track(target_album, 'JPABC260721')
      YtmusicAlbum.create!(
        album: target_album,
        browse_id: 'ytmusic-album-1',
        name: 'YouTube Music Album',
        total_tracks: 1
      )
      apple_music_album = AppleMusicAlbum.create!(
        album: target_album,
        apple_music_id: 'apple-album-yt',
        name: 'Source Apple Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        total_tracks: 1
      )
      AppleMusicTrack.create!(
        album: target_album,
        track: target_album.tracks.first,
        apple_music_album:,
        apple_music_id: 'apple-track-yt',
        name: 'YouTube Missing Source Track',
        label: Album::TOUHOU_MUSIC_LABEL
      )
      skipped_album = create_album('4777777777822')
      create_track(skipped_album, 'JPABC260722')
      processed_jan_codes = []
      result = nil

      with_singleton_method(YtmusicTrack, :process_album, ->(album) { processed_jan_codes << album.jan_code }) do
        result = Admin::Resource.find!('ytmusic_tracks').action_for!('fetch_missing_ytmusic_tracks').run

        assert_predicate result, :success?
      end

      assert_equal [target_album.jan_code], processed_jan_codes
      assert_includes result.message, '- 未検出: 1アルバム'
      assert_includes result.message, 'YouTube Music Album'
      assert_includes result.message, 'YouTube Missing Source Track'
    end

    test 'fetches only Spotify albums that have missing tracks' do
      target_album = create_album('4777777777831')
      create_track(target_album, 'JPABC260731')
      SpotifyAlbum.create!(
        album: target_album,
        spotify_id: 'spotify-album-1',
        album_type: 'album',
        name: 'Spotify Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        total_tracks: 1
      )
      apple_music_album = AppleMusicAlbum.create!(
        album: target_album,
        apple_music_id: 'apple-album-spotify',
        name: 'Source Apple Album',
        label: Album::TOUHOU_MUSIC_LABEL,
        total_tracks: 1
      )
      AppleMusicTrack.create!(
        album: target_album,
        track: target_album.tracks.first,
        apple_music_album:,
        apple_music_id: 'apple-track-spotify',
        name: 'Spotify Missing Source Track',
        label: Album::TOUHOU_MUSIC_LABEL
      )
      skipped_album = create_album('4777777777832')
      create_track(skipped_album, 'JPABC260732')
      fetched_ids = []
      processed_ids = []
      api_album = Struct.new(:id)
      result = nil

      with_singleton_method(RSpotify::Album, :find, lambda { |ids|
        fetched_ids.concat(ids)
        ids.map { |id| api_album.new(id) }
      }) do
        with_singleton_method(SpotifyClient::Album, :process_album, ->(spotify_album) { processed_ids << spotify_album.id }) do
          result = Admin::Resource.find!('spotify_tracks').action_for!('fetch_missing_spotify_tracks').run

          assert_predicate result, :success?
        end
      end

      assert_equal ['spotify-album-1'], fetched_ids
      assert_equal ['spotify-album-1'], processed_ids
      assert_includes result.message, '- 未検出: 1アルバム'
      assert_includes result.message, 'Spotify Album'
      assert_includes result.message, 'Spotify Missing Source Track'
    end

    private

    def create_album(jan_code)
      Album.create!(jan_code:)
    end

    def create_track(album, isrc)
      Track.create!(album:, jan_code: album.jan_code, isrc:)
    end

    def with_singleton_method(object, method_name, replacement)
      original_method = object.method(method_name)
      object.define_singleton_method(method_name, replacement)
      yield
    ensure
      object.define_singleton_method(method_name, original_method)
    end
  end
end
