# frozen_string_literal: true

require 'test_helper'

module Admin
  class ActionTest < ActiveSupport::TestCase
    test 'resolves non Avo admin action classes' do
      Admin::Resource.all.each do |resource|
        resource.actions.each do |action|
          assert_operator action.action_class, :<, Admin::Actions::BaseAction
          assert_not_equal 'Avo::BaseAction', action.action_class.superclass.name
        end
      end
    end

    test 'runs touhou flag action without depending on Avo action implementation' do
      album = Album.create!(jan_code: '4777777777777')
      track = Track.create!(album:, isrc: 'JPABC260601')

      action = Admin::Resource.find!('albums').action_for!('change_touhou_flag')
      result = action.run

      assert_predicate result, :success?
      assert_predicate track.reload, :is_touhou?
      assert_predicate album.reload, :is_touhou?
    end
  end
end
