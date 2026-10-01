# frozen_string_literal: true

require 'application_system_test_case'

module Admin
  class ActionSubmissionTest < ApplicationSystemTestCase
    test 'submits a ready admin action from its page' do
      run_id = nil

      begin
        assert_instance_of ActiveJob::QueueAdapters::TestAdapter, Admin::ActionJob.queue_adapter

        visit admin_resource_action_path('albums', 'change_touhou_flag')

        assert_selector 'h1', text: '東方フラグを変更'
        assert_selector '.admin-action-execution-panel button[type="submit"]:not([disabled])'

        find('.admin-action-execution-panel button[type="submit"]').click
        within('dialog[open]') do
          find('button[data-action="admin-action-confirm#confirm"]').click
        end

        assert_current_path %r{/admin/albums/actions/change_touhou_flag/runs/}
        run_id = current_path.split('/').last

        assert_selector '#admin-action-progress[data-status="queued"]'
      ensure
        RedisPool.get.del("admin:action_runs:#{run_id}") if run_id
      end
    end

    test 'submits a YouTube Music member action from its page' do
      album = Album.create!(jan_code: "admin-ytmusic-system-action-#{SecureRandom.hex(4)}")
      ytmusic_album = YtmusicAlbum.create!(
        album:,
        browse_id: "MPREb_admin_system_action_#{SecureRandom.hex(4)}",
        name: 'Admin YouTube Music Album',
        payload: {}
      )
      run_id = nil

      begin
        assert_instance_of ActiveJob::QueueAdapters::TestAdapter, Admin::ActionJob.queue_adapter

        visit admin_member_resource_action_path('ytmusic_albums', ytmusic_album, 'update_ytmusic_album_payload')

        assert_selector 'h1', text: 'YouTube Music アルバムのペイロードを更新'
        assert_selector '.admin-action-execution-panel button[type="submit"]:not([disabled])'

        find('.admin-action-execution-panel button[type="submit"]').click
        within('dialog[open]') do
          find('button[data-action="admin-action-confirm#confirm"]').click
        end

        assert_current_path %r{/admin/ytmusic_albums/#{ytmusic_album.id}/actions/update_ytmusic_album_payload/runs/}
        run_id = current_path.split('/').last

        assert_selector '#admin-action-progress[data-status="queued"]'
      ensure
        RedisPool.get.del("admin:action_runs:#{run_id}") if run_id
      end
    end
  end
end
