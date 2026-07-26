# frozen_string_literal: true

require 'test_helper'

module SpotifyApi
  class ResponseTest < ActiveSupport::TestCase
    ALBUM_BODY = {
      'id' => '4aawyAB9vmqN3uQ7FjRGTy',
      'name' => 'Global Warming',
      'label' => '東方同人音楽流通',
      'external_ids' => { 'upc' => '4571364253716' },
      'external_urls' => { 'spotify' => 'https://open.spotify.com/album/4aawyAB9vmqN3uQ7FjRGTy' },
      'artists' => [{ 'id' => '0TnOYISbd1XYRBk9myaseg', 'name' => 'Pitbull' }]
    }.freeze

    test 'builds an object with method access for a hash' do
      album = Response.build(ALBUM_BODY)

      assert_equal '4aawyAB9vmqN3uQ7FjRGTy', album.id
      assert_equal 'Global Warming', album.name
      assert_equal '東方同人音楽流通', album.label
    end

    test 'builds an array of objects for an array' do
      albums = Response.build([ALBUM_BODY, ALBUM_BODY])

      assert_equal 2, albums.size
      assert_equal 'Global Warming', albums.first.name
    end

    test 'returns non hash values as they are' do
      assert_nil Response.build(nil)
      assert_equal 'string', Response.build('string')
      assert_equal 42, Response.build(42)
    end

    test 'keeps nested values as raw hashes and arrays' do
      album = Response.build(ALBUM_BODY)

      assert_equal '4571364253716', album.external_ids['upc']
      assert_equal 'https://open.spotify.com/album/4aawyAB9vmqN3uQ7FjRGTy', album.external_urls['spotify']
      assert_equal 'Pitbull', album.artists.first['name']
    end

    test 'as_json returns the raw hash' do
      album = Response.build(ALBUM_BODY)

      assert_equal ALBUM_BODY, album.as_json
      assert_same ALBUM_BODY, album.as_json
    end

    test 'returns nil for an undefined key without raising' do
      album = Response.build(ALBUM_BODY)

      assert_nil album.unknown_attribute
      assert_not_respond_to album, :unknown_attribute
    end

    test 'raises NoMethodError for a call with arguments' do
      album = Response.build(ALBUM_BODY)

      assert_raises(NoMethodError) { album.unknown_attribute('argument') }
    end

    test 'supports key access with both strings and symbols' do
      album = Response.build(ALBUM_BODY)

      assert_equal 'Global Warming', album['name']
      assert_equal 'Global Warming', album[:name]
      assert_nil album[:unknown_attribute]
    end

    test 'key? tells whether the key exists' do
      album = Response.build(ALBUM_BODY)

      assert album.key?('label')
      assert album.key?(:label)
      assert_not album.key?(:unknown_attribute)
    end

    test 'to_h returns the raw hash' do
      album = Response.build(ALBUM_BODY)

      assert_equal ALBUM_BODY, album.to_h
      assert_respond_to album, :name
    end
  end
end
