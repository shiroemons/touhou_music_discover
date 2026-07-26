# frozen_string_literal: true

require 'test_helper'

module Admin
  module Actions
    class FetchYtmusicAlbumDistributionDateActionTest < ActiveSupport::TestCase
      test 'succeeds and reports the distributed_on when the outcome is updated' do
        ytmusic_album = create_ytmusic_album
        ytmusic_album.update!(distributed_on: Date.new(2026, 6, 30), distribution_source: 'majority')
        outcome = DistributionDate::YtmusicCollector::CollectOutcome.new(status: :updated, fetched_count: 2)

        action = run_action_with_outcome(outcome, models: [ytmusic_album])

        message = action.response[:messages]

        assert_equal 1, message.size
        assert_equal :success, message.first[:type]
        assert_includes message.first[:body], ytmusic_album.name
        assert_includes message.first[:body], '2026-06-30'
        assert_includes message.first[:body], 'majority'
      end

      test 'warns when the outcome is failed' do
        ytmusic_album = create_ytmusic_album
        ytmusic_album.update!(distribution_source: 'failed')
        outcome = DistributionDate::YtmusicCollector::CollectOutcome.new(status: :failed, fetched_count: 0)

        action = run_action_with_outcome(outcome, models: [ytmusic_album])

        message = action.response[:messages]

        assert_equal 1, message.size
        assert_equal :warning, message.first[:type]
        assert_includes message.first[:body], ytmusic_album.name
      end

      test 'errors when the outcome is not_found' do
        ytmusic_album = create_ytmusic_album
        outcome = DistributionDate::YtmusicCollector::CollectOutcome.new(status: :not_found, fetched_count: 0)

        action = run_action_with_outcome(outcome, models: [ytmusic_album])

        message = action.response[:messages]

        assert_equal 1, message.size
        assert_equal :error, message.first[:type]
      end

      test 'errors when the outcome is error' do
        ytmusic_album = create_ytmusic_album
        outcome = DistributionDate::YtmusicCollector::CollectOutcome.new(status: :error, fetched_count: 0)

        action = run_action_with_outcome(outcome, models: [ytmusic_album])

        message = action.response[:messages]

        assert_equal 1, message.size
        assert_equal :error, message.first[:type]
      end

      test 'errors when no album can be resolved from args' do
        action = FetchYtmusicAlbumDistributionDate.new
        action.handle(fields: {})

        message = action.response[:messages]

        assert_equal 1, message.size
        assert_equal :error, message.first[:type]
        assert_includes message.first[:body], 'レコードが見つかりませんでした'
      end

      private

      def run_action_with_outcome(outcome, models:)
        fake_collector = Object.new
        fake_collector.define_singleton_method(:collect_album) { |_id| outcome }

        action = FetchYtmusicAlbumDistributionDate.new
        with_singleton_method(DistributionDate::YtmusicCollector, :new, ->(**_kwargs) { fake_collector }) do
          action.handle(models:)
        end
        action
      end

      def create_ytmusic_album
        album = Album.create!(jan_code: "fetch-ytmusic-distribution-#{SecureRandom.hex(4)}")
        YtmusicAlbum.create!(album:, browse_id: "MPREb_fetch_dist_#{SecureRandom.hex(4)}", name: '配信日取得テスト用アルバム')
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
