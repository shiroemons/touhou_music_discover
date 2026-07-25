# frozen_string_literal: true

namespace :db do
  desc 'プラットフォーム別テーブルの重複行を除去する（既定はdry-run。APPLY=1で実削除。MAX_DELETIONS / MAX_RATIO で安全装置の閾値を上書き可能）'
  task dedupe_platform_records: :environment do
    Dedupe::PlatformRecords.new(
      apply: ENV['APPLY'] == '1',
      max_deletions: ENV.fetch('MAX_DELETIONS', Dedupe::PlatformRecords::DEFAULT_MAX_DELETIONS).to_i,
      max_ratio: ENV.fetch('MAX_RATIO', Dedupe::PlatformRecords::DEFAULT_MAX_RATIO).to_f
    ).run
  end
end
