# frozen_string_literal: true

require 'test_helper'

module YtMusic
  class ResponseTest < ActiveSupport::TestCase
    test 'collects only the album shelf when other shelf types are present' do
      shelves = [
        { 'itemSectionRenderer' => {} },
        { 'musicCardShelfRenderer' => { 'title' => { 'runs' => [{ 'text' => 'アルバム' }] } } },
        build_album_shelf(['Album One'])
      ]
      response = Response.new(build_raw_response(shelves))

      assert_equal ['Album One'], response.data[:albums].map(&:title)
    end

    test 'returns an empty hash without raising when contents is nil' do
      raw_response = { 'contents' => nil }

      response = Response.new(raw_response)

      assert_equal({}, response.data)
    end

    test 'returns an empty hash without raising when the tabbed contents path is missing entirely' do
      response = Response.new({})

      assert_equal({}, response.data)
    end

    test 'collects songs with their album browse IDs from a song shelf' do
      response = Response.new(build_raw_response([build_song_shelf]))
      song = response.data[:songs].first

      assert_equal 'sine nomine（feat. Annabel、凋叶棕）', song.title
      assert_equal 'T7SbAuozdZQ', song.video_id
      assert_equal 'MPREb_Jj8jX1CpWxn', song.album_browse_id
      assert_equal 'sine nomine', song.album_title
      assert_equal ['東方LostWord'], song.artists.map(&:name)
    end

    test 'raises a clear error when the response is not a JSON object' do
      error = assert_raises(ArgumentError) { Response.new('Forbidden') }

      assert_equal 'YouTube Music response must be a Hash, got String', error.message
    end

    private

    def build_raw_response(contents)
      {
        'contents' => {
          'tabbedSearchResultsRenderer' => {
            'tabs' => [
              {
                'tabRenderer' => {
                  'content' => {
                    'sectionListRenderer' => { 'contents' => contents }
                  }
                }
              }
            ]
          }
        }
      }
    end

    def build_album_shelf(titles)
      {
        'musicShelfRenderer' => {
          'title' => { 'runs' => [{ 'text' => 'アルバム' }] },
          'contents' => titles.map { |title| { 'musicResponsiveListItemRenderer' => build_simple_album_item(title) } }
        }
      }
    end

    def build_simple_album_item(title)
      {
        'flexColumns' => [
          {
            'musicResponsiveListItemFlexColumnRenderer' => {
              'text' => { 'runs' => [{ 'text' => title }] }
            }
          },
          {
            'musicResponsiveListItemFlexColumnRenderer' => {
              'text' => { 'runs' => [{ 'text' => 'アルバム' }, { 'text' => ' • ' }, { 'text' => '2026' }] }
            }
          }
        ]
      }
    end

    def build_song_shelf
      {
        'musicShelfRenderer' => {
          'title' => { 'runs' => [{ 'text' => '曲' }] },
          'contents' => [
            {
              'musicResponsiveListItemRenderer' => {
                'flexColumns' => [
                  {
                    'musicResponsiveListItemFlexColumnRenderer' => {
                      'text' => { 'runs' => [{ 'text' => 'sine nomine（feat. Annabel、凋叶棕）' }] }
                    }
                  },
                  {
                    'musicResponsiveListItemFlexColumnRenderer' => {
                      'text' => {
                        'runs' => [
                          artist_run('東方LostWord', 'UCasN8o_lLTIBGRZJKHF0sUQ'),
                          { 'text' => ' • ' },
                          artist_run('sine nomine', 'MPREb_Jj8jX1CpWxn'),
                          { 'text' => ' • ' },
                          { 'text' => '4:41' }
                        ]
                      }
                    }
                  }
                ],
                'playlistItemData' => { 'videoId' => 'T7SbAuozdZQ' }
              }
            }
          ]
        }
      }
    end

    def artist_run(text, browse_id)
      {
        'text' => text,
        'navigationEndpoint' => {
          'browseEndpoint' => { 'browseId' => browse_id }
        }
      }
    end
  end
end
