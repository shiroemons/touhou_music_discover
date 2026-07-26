# frozen_string_literal: true

require 'test_helper'

module SpotifyApi
  class PageTest < ActiveSupport::TestCase
    ITEM = { 'id' => '1', 'name' => 'track' }.freeze

    PAGING_BODY = {
      'items' => [ITEM],
      'total' => 42,
      'limit' => 20,
      'offset' => 0,
      'next' => 'https://api.spotify.com/v1/albums/1/tracks?offset=20&limit=20'
    }.freeze

    test 'wraps items with Response and exposes total / limit / offset' do
      page = Page.build(PAGING_BODY)

      assert_instance_of Response, page.items.first
      assert_equal '1', page.items.first.id
      assert_equal 42, page.total
      assert_equal 20, page.limit
      assert_equal 0, page.offset
    end

    test 'keeps the raw body for debugging and payload use cases' do
      page = Page.build(PAGING_BODY)

      assert_same PAGING_BODY, page.body
    end

    test 'delegates Enumerable methods to items' do
      page = Page.build(PAGING_BODY)

      assert_equal 1, page.size
      assert_not page.empty?
      assert_equal ['1'], page.map(&:id)
    end

    test 'last_page? is true when next is absent' do
      page = Page.build(PAGING_BODY.merge('next' => nil))

      assert_predicate page, :last_page?
    end

    test 'last_page? is false when next is present' do
      page = Page.build(PAGING_BODY)

      assert_not page.last_page?
    end

    test 'build tolerates a nil body' do
      page = Page.build(nil)

      assert_equal [], page.items
      assert_nil page.total
      assert_empty page
      assert_predicate page, :last_page?
    end

    test 'build tolerates a body without items' do
      page = Page.build({ 'total' => 0 })

      assert_equal [], page.items
      assert_equal 0, page.total
      assert_empty page
    end
  end
end
