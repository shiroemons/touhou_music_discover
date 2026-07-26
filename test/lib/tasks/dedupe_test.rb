# frozen_string_literal: true

require 'test_helper'
require 'rake'

class DedupeTaskTest < ActiveSupport::TestCase
  Rake::Task.define_task(:environment)
  load Rails.root.join('lib/tasks/dedupe.rake')

  setup do
    Rake::Task['db:dedupe_platform_records'].reenable
  end

  test 'APPLY未指定の実行はdry-runとなりレコードを削除しない' do
    create_apple_music_album_duplicates

    output, = capture_io do
      assert_no_difference 'AppleMusicAlbum.unscoped.count' do
        Rake::Task['db:dedupe_platform_records'].invoke
      end
    end

    assert_match 'DRY-RUN', output
    assert_match 'AppleMusicAlbum', output
    assert_match '連鎖削除予定', output
  end

  private

  # unique index 下で重複行を意図的に作るためのテスト専用ヘルパー。
  # PostgreSQLのDDLはトランザクション対応で、各テストはトランザクション内で実行されロールバックされるため、
  # ここで外したindexはテスト終了時に自動的に復元される（明示的なteardownは不要）。
  def create_apple_music_album_duplicates
    album = Album.create!(jan_code: "dedupe-task-#{SecureRandom.hex(6)}")
    apple_music_id = "dedupe-task-am-#{SecureRandom.hex(4)}"

    ActiveRecord::Base.connection.remove_index(:apple_music_albums, name: 'index_apple_music_albums_on_apple_music_id')
    2.times do
      AppleMusicAlbum.create!(album:, apple_music_id:, name: 'Dedupe Task Album', label: Album::TOUHOU_MUSIC_LABEL)
    end
  end
end
