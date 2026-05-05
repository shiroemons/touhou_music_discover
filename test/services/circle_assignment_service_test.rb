# frozen_string_literal: true

require 'test_helper'

class CircleAssignmentServiceTest < ActiveSupport::TestCase
  setup do
    CirclesAlbum.delete_all
    AppleMusicAlbum.delete_all
    SpotifyAlbum.delete_all
    Album.delete_all
    Circle.delete_all
  end

  test 'assigns circle from Apple Music artist name when Spotify album is missing' do
    album = Album.create!(jan_code: '1111111111111')
    circle = Circle.create!(name: 'Apple Circle')
    AppleMusicAlbum.create!(
      album:,
      apple_music_id: 'apple-music-album-1',
      name: 'Apple Music Album',
      label: Album::TOUHOU_MUSIC_LABEL,
      payload: {
        'attributes' => {
          'artistName' => circle.name
        }
      }
    )

    CircleAssignmentService.new.assign_missing

    assert_equal [circle], album.reload.circles.to_a
  end

  test 'keeps JAN mapping fallback when streaming artists do not match circles' do
    album = Album.create!(jan_code: '4580547313864')
    circle = Circle.create!(name: '少女フラクタル')
    AppleMusicAlbum.create!(
      album:,
      apple_music_id: 'apple-music-album-2',
      name: 'Apple Music Album',
      label: Album::TOUHOU_MUSIC_LABEL,
      payload: {
        'attributes' => {
          'artistName' => 'Unknown Artist'
        }
      }
    )

    CircleAssignmentService.new.assign_missing

    assert_equal [circle], album.reload.circles.to_a
  end
end
