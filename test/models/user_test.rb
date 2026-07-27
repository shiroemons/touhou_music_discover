# frozen_string_literal: true

require 'test_helper'

class UserTest < ActiveSupport::TestCase
  def auth_hash(overrides = {})
    base = {
      provider: 'spotify',
      uid: 'test-user',
      info: {
        id: 'test-user',
        display_name: 'Test User',
        email: 'test@example.com',
        images: [{ 'url' => 'https://example.test/avatar.png' }]
      }
    }
    base[:info] = base[:info].merge(overrides.delete(:info) || {})
    base.merge(overrides)
  end

  test 'creates a user from the auth hash' do
    user = User.find_or_create_from_auth_hash(auth_hash)

    assert_equal 'spotify', user.provider
    assert_equal 'test-user', user.uid
    assert_equal 'Test User', user.nickname
    assert_equal 'test-user', user.name
    assert_equal 'test@example.com', user.email
    assert_equal 'https://example.test/avatar.png', user.image_url
  end

  test 'updates attributes of an existing user' do
    User.find_or_create_from_auth_hash(auth_hash)

    updated = User.find_or_create_from_auth_hash(
      auth_hash(info: { display_name: 'Renamed User',
                        images: [{ 'url' => 'https://example.test/new.png' }] })
    )

    assert_equal 1, User.where(provider: 'spotify', uid: 'test-user').count
    assert_equal 'Renamed User', updated.nickname
    assert_equal 'https://example.test/new.png', updated.image_url
  end

  test 'tolerates a user without a profile image' do
    user = User.find_or_create_from_auth_hash(auth_hash(info: { images: [] }))

    assert_equal '', user.image_url
  end

  test 'tolerates a missing images key' do
    hash = auth_hash
    hash[:info].delete(:images)

    user = User.find_or_create_from_auth_hash(hash)

    assert_equal '', user.image_url
  end

  test 'falls back to an empty email when Spotify omits it' do
    user = User.find_or_create_from_auth_hash(auth_hash(info: { email: nil }))

    assert_equal '', user.email
  end

  test 'falls back to the Spotify id when display_name is missing' do
    user = User.find_or_create_from_auth_hash(auth_hash(info: { display_name: nil }))

    assert_equal 'test-user', user.nickname
  end
end
