# frozen_string_literal: true

require 'test_helper'

class CircleAssignmentServiceTest < ActiveSupport::TestCase
  setup do
    CirclesAlbum.delete_all
    AppleMusicAlbum.delete_all
    LineMusicAlbum.delete_all
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

    result = CircleAssignmentService.new.assign_missing

    assert_equal [circle], album.reload.circles.to_a
    assert_equal({ processed: 1, assigned: 1, unassigned: 0 }, result)
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

    result = CircleAssignmentService.new.assign_missing

    assert_equal [circle], album.reload.circles.to_a
    assert_equal({ processed: 1, assigned: 1, unassigned: 0 }, result)
  end

  test 'assigns circle from LINE MUSIC artist when other services use Various Artists' do
    album = Album.create!(jan_code: '4582736138869')
    circle = Circle.create!(name: '甘夏 -アマナツ-')
    SpotifyAlbum.create!(
      album:,
      spotify_id: 'spotify-various-artists-album',
      album_type: 'album',
      name: 'Elektro Fox',
      label: Album::TOUHOU_MUSIC_LABEL,
      payload: {
        'artists' => [
          { 'name' => 'Various Artists' }
        ]
      }
    )
    AppleMusicAlbum.create!(
      album:,
      apple_music_id: 'apple-various-artists-album',
      name: 'Elektro Fox - EP',
      label: Album::TOUHOU_MUSIC_LABEL,
      payload: {
        'attributes' => {
          'artistName' => 'Various Artists'
        }
      }
    )
    LineMusicAlbum.create!(
      album:,
      line_music_id: 'line-music-amanatsu-album',
      name: 'Elektro Fox',
      payload: {
        'artists' => [
          { 'artist_name' => circle.name }
        ]
      }
    )

    result = CircleAssignmentService.new.assign_missing

    assert_equal [circle], album.reload.circles.to_a
    assert_equal({ processed: 1, assigned: 1, unassigned: 0 }, result)
  end

  test 'admin action reports assigned and unassigned album counts' do
    circle = Circle.create!(name: 'Assignable Circle')
    assignable_album = Album.create!(jan_code: '1111111111112')
    Album.create!(jan_code: '1111111111113')
    AppleMusicAlbum.create!(
      album: assignable_album,
      apple_music_id: 'apple-assignable-album',
      name: 'Assignable Album',
      label: Album::TOUHOU_MUSIC_LABEL,
      payload: {
        'attributes' => {
          'artistName' => circle.name
        }
      }
    )

    result = Admin::Resource.find!('albums').action_for!('set_circles').run

    assert_equal :warning, result.status
    assert_equal(
      '処理完了: 対象2件、設定1件、未設定1件。' \
      '未設定アルバムは、配信サービスのアーティスト名またはJAN対応表を確認してください。',
      result.message
    )
  end

  test 'counts an album with missing LINE MUSIC payload as unassigned' do
    album = Album.create!(jan_code: '1111111111114')
    LineMusicAlbum.create!(
      album:,
      line_music_id: 'line-music-missing-payload',
      name: 'Missing Payload Album',
      payload: nil
    )

    result = CircleAssignmentService.new.assign_missing

    assert_empty album.reload.circles
    assert_equal({ processed: 1, assigned: 0, unassigned: 1 }, result)
  end
end
