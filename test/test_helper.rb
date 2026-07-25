# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # ParallelRunner を使うコードは、テストでは常に逐次実行 (records.each) にする。
    # Parallel gem を一切呼ばないため、fork や別スレッドに起因する非決定性がなくなり、
    # 各テストが同一プロセス・同一トランザクション内で決定的に動作する。
    ParallelRunner.forced_workers = 1

    # Add more helper methods to be used by all tests here...
  end
end
