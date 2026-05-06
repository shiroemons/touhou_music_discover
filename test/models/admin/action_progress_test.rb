# frozen_string_literal: true

require 'test_helper'

module Admin
  class ActionProgressTest < ActiveSupport::TestCase
    test 'records current and total from action messages' do
      updates = []
      with_action_run_method(:update!, ->(_run_id, attrs) { updates << attrs }) do
        progress = Admin::ActionProgress.new('run-id')

        progress.record_message('Spotify アルバム: 25/100 Progress: 25.0%')
      end

      assert_equal 25, updates.last.fetch(:current)
      assert_equal 100, updates.last.fetch(:total)
      assert_equal 'Spotify アルバム: 25/100 Progress: 25.0%', updates.last.fetch(:message)
    end

    test 'treats warning action results as completed runs' do
      update_attrs = nil
      result = Admin::ActionResult.new(status: :warning, message: 'partial success')

      with_action_run_method(:find!, ->(_run_id) { { 'total' => 10, 'current' => 8 } }) do
        with_action_run_method(:update!, ->(_run_id, attrs) { update_attrs = attrs }) do
          Admin::ActionRun.complete!('run-id', result)
        end
      end

      assert_equal 'completed', update_attrs.fetch(:status)
      assert_equal 10, update_attrs.fetch(:current)
      assert_equal 'warning', update_attrs.fetch(:result_status)
    end

    private

    def with_action_run_method(method_name, replacement)
      original = Admin::ActionRun.method(method_name)
      Admin::ActionRun.define_singleton_method(method_name, replacement)
      yield
    ensure
      Admin::ActionRun.define_singleton_method(method_name, original)
    end
  end
end
