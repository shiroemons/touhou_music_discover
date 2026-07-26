# frozen_string_literal: true

require 'test_helper'

module YtMusic
  class AlbumTest < ActiveSupport::TestCase
    FakeTrack = Struct.new(:playable) do
      def playable?
        playable
      end
    end

    test 'degraded? is false when at least one track is playable' do
      album = build_album_with_tracks([FakeTrack.new(true), FakeTrack.new(false)])

      assert_not album.degraded?
    end

    test 'degraded? is true when no tracks are playable' do
      album = build_album_with_tracks([FakeTrack.new(false), FakeTrack.new(false)])

      assert_predicate album, :degraded?
    end

    test 'degraded? is true when tracks is empty' do
      album = build_album_with_tracks([])

      assert_predicate album, :degraded?
    end

    test 'degraded? is true when tracks is nil' do
      album = build_album_with_tracks(nil)

      assert_predicate album, :degraded?
    end

    test 'playable_track_count counts only playable tracks' do
      album = build_album_with_tracks([FakeTrack.new(true), FakeTrack.new(true), FakeTrack.new(false)])

      assert_equal 2, album.playable_track_count
    end

    test 'playable_track_count is 0 when tracks is nil' do
      album = build_album_with_tracks(nil)

      assert_equal 0, album.playable_track_count
    end

    test 'playable_track_count is 0 when tracks is empty' do
      album = build_album_with_tracks([])

      assert_equal 0, album.playable_track_count
    end

    test 'degraded? is false via real Track parsing when playlist_id is missing on every track' do
      response = build_response(
        artist_texts: ['Album Artist'],
        track_artist_texts: [nil, nil],
        track_playlist_ids: [nil, nil]
      )

      album = Album.new(response)

      assert_equal [nil, nil], album.tracks.map(&:playlist_id)
      assert(album.tracks.all? { |track| track.video_id.present? && track.track_number.to_i.positive? })
      assert_not album.degraded?
    end

    test 'tracks without their own artist column inherit the album artists' do
      response = build_response(
        artist_texts: ['Album Artist'],
        track_artist_texts: [nil, nil]
      )

      album = Album.new(response)

      assert_equal ['Album Artist'], album.artists.map(&:name)
      album.tracks.each do |track|
        assert_equal album.artists, track.artists
      end
    end

    test 'missing straplineTextOne still sets tracks, thumbnails and playlist_url, with artists empty' do
      response = build_response(artist_texts: nil, track_artist_texts: [nil])

      album = Album.new(response)

      assert_equal [], album.artists
      assert_equal 1, album.tracks.size
      assert_equal 1, album.thumbnails.size
      assert_equal 'https://music.youtube.com/playlist?list=test', album.playlist_url
    end

    private

    def build_album_with_tracks(tracks)
      Album.allocate.tap { it.instance_variable_set(:@tracks, tracks) }
    end

    def build_response(artist_texts:, track_artist_texts:, track_playlist_ids: nil)
      strapline = if artist_texts.nil?
                    nil
                  else
                    { 'runs' => artist_texts.map { |text| { 'text' => text } } }
                  end

      header = {
        'title' => { 'runs' => [{ 'text' => 'Album Title' }] },
        'subtitle' => { 'runs' => [{ 'text' => 'アルバム' }, { 'text' => ' • ' }, { 'text' => '2026' }] },
        'straplineTextOne' => strapline,
        'secondSubtitle' => { 'runs' => [{ 'text' => track_artist_texts.size.to_s }, { 'text' => ' • ' }, { 'text' => '10:00' }] },
        'thumbnail' => {
          'musicThumbnailRenderer' => {
            'thumbnail' => { 'thumbnails' => [{ 'url' => 'https://example.com/thumb.jpg', 'width' => 100, 'height' => 100 }] }
          }
        }
      }

      track_playlist_ids ||= Array.new(track_artist_texts.size, 'PLAYLIST')
      track_contents = track_artist_texts.each_with_index.map { |texts, index| build_track_item(texts, playlist_id: track_playlist_ids[index]) }

      {
        'contents' => {
          'twoColumnBrowseResultsRenderer' => {
            'tabs' => [
              {
                'tabRenderer' => {
                  'content' => {
                    'sectionListRenderer' => {
                      'contents' => [
                        { 'musicResponsiveHeaderRenderer' => header }
                      ]
                    }
                  }
                }
              }
            ],
            'secondaryContents' => {
              'sectionListRenderer' => {
                'contents' => [
                  { 'musicShelfRenderer' => { 'contents' => track_contents } }
                ]
              }
            }
          }
        },
        'microformat' => {
          'microformatDataRenderer' => { 'urlCanonical' => 'https://music.youtube.com/playlist?list=test' }
        }
      }
    end

    def build_track_item(artist_texts, playlist_id: 'PLAYLIST')
      flex_columns = [
        {
          'musicResponsiveListItemFlexColumnRenderer' => {
            'text' => { 'runs' => [{ 'text' => 'Track Title', 'navigationEndpoint' => { 'watchEndpoint' => { 'videoId' => 'VIDEO', 'playlistId' => playlist_id } } }] }
          }
        }
      ]
      flex_columns[1] = {
        'musicResponsiveListItemFlexColumnRenderer' => {
          'text' => artist_texts.nil? ? {} : { 'runs' => artist_texts.map { |text| { 'text' => text } } }
        }
      }

      {
        'musicResponsiveListItemRenderer' => {
          'flexColumns' => flex_columns,
          'fixedColumns' => [
            { 'musicResponsiveListItemFixedColumnRenderer' => { 'text' => { 'runs' => [{ 'text' => '3:30' }] } } }
          ],
          'index' => { 'runs' => [{ 'text' => '1' }] }
        }
      }
    end
  end
end
