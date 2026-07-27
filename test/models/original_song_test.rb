# frozen_string_literal: true

require 'test_helper'

class OriginalSongTest < ActiveSupport::TestCase
  test 'playlist_titles excludes duplicated songs' do
    original = Original.create!(code: 'TEST_ORIG', title: 'テスト作品', short_title: 'テスト作品',
                                original_type: :windows, series_order: 9999)
    OriginalSong.create!(code: 'TEST_S1', original_code: original.code, title: 'ユニーク原曲',
                         track_number: 1, is_duplicate: false)
    OriginalSong.create!(code: 'TEST_S2', original_code: original.code, title: '重複のみ原曲',
                         track_number: 2, is_duplicate: true)

    titles = OriginalSong.playlist_titles

    assert_includes titles, 'ユニーク原曲'
    assert_not_includes titles, '重複のみ原曲'
  end

  test 'playlist_code_for returns the code of a non-duplicated song' do
    original = Original.create!(code: 'TEST_ORIG3', title: 'テスト作品3', short_title: 'テスト作品3',
                                original_type: :windows, series_order: 9997)
    OriginalSong.create!(code: 'TEST_S4', original_code: original.code, title: 'コード引き原曲',
                         track_number: 1, is_duplicate: false)

    assert_equal 'TEST_S4', OriginalSong.playlist_code_for('コード引き原曲')
    assert_nil OriginalSong.playlist_code_for('存在しないプレイリスト名')
  end

  test 'playlist_code_map maps titles to codes without duplicated songs' do
    original = Original.create!(code: 'TEST_ORIG4', title: 'テスト作品4', short_title: 'テスト作品4',
                                original_type: :windows, series_order: 9996)
    OriginalSong.create!(code: 'TEST_S5', original_code: original.code, title: 'マップ原曲',
                         track_number: 1, is_duplicate: false)
    OriginalSong.create!(code: 'TEST_S6', original_code: original.code, title: 'マップ重複原曲',
                         track_number: 2, is_duplicate: true)

    map = OriginalSong.playlist_code_map

    assert_equal 'TEST_S5', map['マップ原曲']
    assert_not map.key?('マップ重複原曲')
  end
end
