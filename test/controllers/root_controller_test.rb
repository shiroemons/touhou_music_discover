# frozen_string_literal: true

require 'test_helper'

class RootControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(provider: 'spotify', uid: 'root-test-user', name: 'Root Test User',
                         nickname: 'Root Test User', email: 'root-test@example.com', image_url: '')
  end

  test 'renders playlist update actions as submit buttons to prevent duplicate submissions' do
    post '/test_login', params: { user_id: @user.id }

    get root_path

    assert_response :success
    assert_select 'link[rel="icon"][href="/icon.svg"]', minimum: 1
    assert_select 'form.update-card-form[method="post"]', count: 5
    assert_select 'form.update-card-form button.update-card[type="submit"]', count: 5
    assert_select 'a.update-card', count: 0

    %w[windows pc98 zuns_music_collection akyus_untouched_score commercial_books].each do |update_type|
      assert_select 'form[action=?]', spotify_playlists_create_path(update_type:), count: 1
    end
  end
end
