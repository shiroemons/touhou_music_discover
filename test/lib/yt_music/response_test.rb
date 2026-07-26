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
  end
end
