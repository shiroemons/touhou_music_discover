# frozen_string_literal: true

require 'test_helper'

module YtMusic
  class TrackTest < ActiveSupport::TestCase
    test 'extracts video_id, playlist_id and track_number from a normal response' do
      track = Track.new(build_content(
                          flex_navigation: { 'videoId' => 'VIDEO1', 'playlistId' => 'PLAYLIST1' },
                          index_text: '1'
                        ))

      assert_equal 'VIDEO1', track.video_id
      assert_equal 'PLAYLIST1', track.playlist_id
      assert_equal 1, track.track_number
      assert_predicate track, :complete?
    end

    test 'falls back to playlistItemData for video_id when flexColumn navigationEndpoint is missing' do
      track = Track.new(build_content(
                          flex_navigation: nil,
                          playlist_item_data: { 'videoId' => 'VIDEO2' },
                          index_text: '2'
                        ))

      assert_equal 'VIDEO2', track.video_id
      assert_nil track.playlist_id
      assert_not track.complete?
    end

    test 'falls back to the overlay play button when flexColumn and playlistItemData are missing' do
      track = Track.new(build_content(
                          flex_navigation: nil,
                          playlist_item_data: nil,
                          overlay_navigation: { 'videoId' => 'VIDEO3', 'playlistId' => 'PLAYLIST3' },
                          index_text: '3'
                        ))

      assert_equal 'VIDEO3', track.video_id
      assert_equal 'PLAYLIST3', track.playlist_id
      assert_equal 3, track.track_number
      assert_predicate track, :complete?
    end

    test 'track_number is nil without raising when index is missing' do
      track = Track.new(build_content(
                          flex_navigation: { 'videoId' => 'VIDEO4', 'playlistId' => 'PLAYLIST4' },
                          index_text: nil
                        ))

      assert_nil track.track_number
      assert_not track.complete?
    end

    test 'playable? is true when video_id and track_number are present even without playlist_id' do
      track = Track.new(build_content(
                          flex_navigation: { 'videoId' => 'VIDEO5' },
                          index_text: '1'
                        ))

      assert_nil track.playlist_id
      assert_predicate track, :playable?
    end

    test 'playable? is false when video_id is missing' do
      track = Track.new(build_content(
                          flex_navigation: nil,
                          index_text: '1'
                        ))

      assert_not track.playable?
    end

    test 'playable? is false when track_number is nil' do
      track = Track.new(build_content(
                          flex_navigation: { 'videoId' => 'VIDEO6', 'playlistId' => 'PLAYLIST6' },
                          index_text: nil
                        ))

      assert_not track.playable?
    end

    test 'playable? is false when track_number is 0' do
      track = Track.new(build_content(
                          flex_navigation: { 'videoId' => 'VIDEO7', 'playlistId' => 'PLAYLIST7' },
                          index_text: '0'
                        ))

      assert_not track.playable?
    end

    test 'uses the track-specific artist column when present, ignoring album_artists' do
      album_artists = [Artist.new({ 'text' => 'Album Artist' })]
      track = Track.new(
        build_content(artist_texts: ['Track Artist']),
        album_artists:
      )

      assert_equal ['Track Artist'], track.artists.map(&:name)
    end

    test 'falls back to album_artists when the track has no artist column runs' do
      album_artists = [Artist.new({ 'text' => 'Album Artist' })]
      track = Track.new(build_content(artist_texts: nil), album_artists:)

      assert_equal album_artists, track.artists
    end

    test 'artists is nil when neither the track nor album_artists provide artists' do
      track = Track.new(build_content(artist_texts: nil))

      assert_nil track.artists
    end

    test 'extracts a plain integer view_count from "再生回数 17 回"' do
      track = Track.new(build_content(view_count_text: '再生回数 17 回'))

      assert_equal '再生回数 17 回', track.view_count_text
      assert_equal 17, track.view_count
    end

    test 'extracts view_count in 万 units from "再生回数 1.2万 回"' do
      track = Track.new(build_content(view_count_text: '再生回数 1.2万 回'))

      assert_equal 12_000, track.view_count
    end

    test 'extracts view_count in 万 units from "再生回数 2302万 回"' do
      track = Track.new(build_content(view_count_text: '再生回数 2302万 回'))

      assert_equal 23_020_000, track.view_count
    end

    test 'extracts view_count with a fractional 万 unit from "再生回数 6.5万 回"' do
      track = Track.new(build_content(view_count_text: '再生回数 6.5万 回'))

      assert_equal 65_000, track.view_count
    end

    test 'extracts view_count from a comma-separated number "再生回数 1,234 回"' do
      track = Track.new(build_content(view_count_text: '再生回数 1,234 回'))

      assert_equal 1234, track.view_count
    end

    test 'view_count is nil when the text has no digits at all' do
      track = Track.new(build_content(view_count_text: 'アーティスト名'))

      assert_equal 'アーティスト名', track.view_count_text
      assert_nil track.view_count
    end

    test 'view_count_text and view_count are nil when flexColumns[2] is missing' do
      track = Track.new(build_content(view_count_text: nil))

      assert_nil track.view_count_text
      assert_nil track.view_count
    end

    private

    def build_content(flex_navigation: nil, playlist_item_data: nil, overlay_navigation: nil, **extra)
      flex_run = { 'text' => 'Song Title' }
      flex_run['navigationEndpoint'] = { 'watchEndpoint' => flex_navigation } if flex_navigation

      flex_columns = [
        {
          'musicResponsiveListItemFlexColumnRenderer' => {
            'text' => { 'runs' => [flex_run] }
          }
        }
      ]
      flex_columns[1] = build_artist_column(extra[:artist_texts]) if extra.key?(:artist_texts)
      flex_columns[2] = build_view_count_column(extra[:view_count_text]) if extra.key?(:view_count_text)

      item = { 'flexColumns' => flex_columns }
      item['playlistItemData'] = playlist_item_data if playlist_item_data
      if overlay_navigation
        item['overlay'] = {
          'musicItemThumbnailOverlayRenderer' => {
            'content' => {
              'musicPlayButtonRenderer' => {
                'playNavigationEndpoint' => { 'watchEndpoint' => overlay_navigation }
              }
            }
          }
        }
      end
      item['index'] = { 'runs' => [{ 'text' => extra[:index_text] }] } if extra[:index_text]

      { 'musicResponsiveListItemRenderer' => item }
    end

    def build_artist_column(artist_texts)
      runs = artist_texts&.map { |text| { 'text' => text } }

      {
        'musicResponsiveListItemFlexColumnRenderer' => {
          'text' => runs ? { 'runs' => runs } : {}
        }
      }
    end

    def build_view_count_column(view_count_text)
      return nil if view_count_text.nil?

      {
        'musicResponsiveListItemFlexColumnRenderer' => {
          'text' => { 'runs' => [{ 'text' => view_count_text }] }
        }
      }
    end
  end
end
