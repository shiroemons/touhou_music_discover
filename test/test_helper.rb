# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'
require 'webmock/minitest'
require 'vcr'

# テストから実 Spotify API を叩くとクォータを消費し、実プレイリストを壊しうる。
# 未スタブのリクエストはすべて例外にして構造的に防ぐ。
WebMock.disable_net_connect!(allow_localhost: true)

# VCR は「実 API のレスポンス形状を起こす」ローカル専用ツール。
# カセットは .gitignore 対象で、コミット済みのテストはどれもカセットに依存しない。
VCR.configure do |config|
  config.cassette_library_dir = Rails.root.join('test/vcr_cassettes').to_s
  config.hook_into :webmock
  config.default_cassette_options = { record: :none }
  config.filter_sensitive_data('<CLIENT_ID>') { ENV.fetch('SPOTIFY_CLIENT_ID', nil) }
  config.filter_sensitive_data('<CLIENT_SECRET>') { ENV.fetch('SPOTIFY_CLIENT_SECRET', nil) }
  config.filter_sensitive_data('<ACCESS_TOKEN>') do |interaction|
    interaction.request.headers['Authorization']&.first&.delete_prefix('Bearer ')
  end
end

Rails.root.glob('test/support/**/*.rb').each { |f| require f }

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # ParallelRunner を使うコードは、テストでは常に逐次実行 (records.each) にする。
    # Parallel gem を一切呼ばないため、fork や別スレッドに起因する非決定性がなくなり、
    # 各テストが同一プロセス・同一トランザクション内で決定的に動作する。
    ParallelRunner.forced_workers = 1

    include SpotifyApiStubs
  end
end
