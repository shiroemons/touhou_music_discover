# frozen_string_literal: true

require 'test_helper'

class AlbumsControllerTest < ActionDispatch::IntegrationTest
  test 'marks album list headers as columns' do
    get albums_path

    assert_response :success
    assert_equal(
      ['JAN', 'Circle', 'Spotify', 'Apple Music', 'YouTube Music', 'LINE MUSIC'],
      css_select('table thead th').map { |header| header.text.strip }
    )
    assert_select 'table thead th[scope=?]', 'col', count: 6
  end

  test 'explains when no albums are available' do
    Album.delete_all

    get albums_path

    assert_response :success
    assert_select 'table tbody tr td[colspan=?]', '6', text: 'No albums are available.'
  end
end
