# frozen_string_literal: true

require 'test_helper'

module Admin
  module Actions
    class FetchYtmusicDistributionDatesActionTest < ActiveSupport::TestCase
      test 'summarizes counts and warns when there are failed or errored albums' do
        result = {
          target_count: 5, updated: 3, failed: 1, not_found: 0, error: 1, fetched_videos: 10,
          applied: true, all: false, only_missing: true, elapsed: 1.0, failed_album_browse_ids: []
        }
        fake_collector = fake_collector_returning(result)

        action = FetchYtmusicDistributionDates.new
        with_singleton_method(DistributionDate::YtmusicCollector, :new, ->(**_kwargs) { fake_collector }) do
          action.handle({})
        end

        message = action.response[:messages]

        assert_equal 1, message.size
        assert_equal :warning, message.first[:type]
        assert_includes message.first[:body], '対象 5件'
        assert_includes message.first[:body], '更新 3件'
        assert_includes message.first[:body], '配信日算出失敗 1件'
        assert_includes message.first[:body], 'エラー 1件'
        assert_includes message.first[:body], '取得動画数 10件'
      end

      test 'succeeds when there are no failed or errored albums' do
        result = {
          target_count: 3, updated: 3, failed: 0, not_found: 0, error: 0, fetched_videos: 6,
          applied: true, all: false, only_missing: true, elapsed: 1.0, failed_album_browse_ids: []
        }
        fake_collector = fake_collector_returning(result)

        action = FetchYtmusicDistributionDates.new
        with_singleton_method(DistributionDate::YtmusicCollector, :new, ->(**_kwargs) { fake_collector }) do
          action.handle({})
        end

        message = action.response[:messages]

        assert_equal 1, message.size
        assert_equal :success, message.first[:type]
      end

      private

      def fake_collector_returning(result)
        collector = Object.new
        collector.define_singleton_method(:run) { result }
        collector
      end

      def with_singleton_method(object, method_name, replacement)
        original_method = object.method(method_name)
        object.define_singleton_method(method_name, replacement)
        yield
      ensure
        object.define_singleton_method(method_name, original_method)
      end
    end
  end
end
