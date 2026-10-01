# frozen_string_literal: true

require_relative '../test_helper'

class ParallelRunnerRealModesCheck < ActiveSupport::TestCase
  parallelize(workers: 1)

  test 'process and thread modes use database and Redis connections' do
    assert_equal 1, ActiveRecord::Base.connection.select_value('SELECT 1').to_i
    assert_equal 'PONG', RedisPool.with(&:ping)

    %i[processes threads].each do |mode|
      results = run_mode(mode)

      assert_equal %w[first second], results.keys.sort
      connections_available = results.values.all? do |pid, thread_id, database_result, redis_result|
        database_result == 1 && redis_result == 'PONG' &&
          (mode == :processes ? pid != Process.pid : pid == Process.pid && thread_id != Thread.current.object_id)
      end

      assert connections_available
      assert_equal 1, ActiveRecord::Base.connection.select_value('SELECT 1').to_i
      assert_equal 'PONG', RedisPool.with(&:ping)
    end
  end

  private

  def run_mode(mode)
    previous_workers = ParallelRunner.forced_workers
    previous_env_workers = ENV.fetch('PARALLEL_WORKERS', nil)
    original_processor_count = Parallel.method(:processor_count)
    ParallelRunner.forced_workers = nil
    ENV.delete('PARALLEL_WORKERS')
    Parallel.define_singleton_method(:processor_count, -> { 2 })

    results = {}
    mutex = Mutex.new
    finish = ->(item, _index, result) { mutex.synchronize { results[item] = result } }

    ParallelRunner.each(%w[first second], workers: 2, mode:, finish:) do
      database_result = ActiveRecord::Base.connection_pool.with_connection do |connection|
        connection.select_value('SELECT 1').to_i
      end
      redis_result = RedisPool.with(&:ping)
      [Process.pid, Thread.current.object_id, database_result, redis_result]
    end

    results
  ensure
    ParallelRunner.forced_workers = previous_workers
    previous_env_workers.nil? ? ENV.delete('PARALLEL_WORKERS') : ENV['PARALLEL_WORKERS'] = previous_env_workers
    Parallel.define_singleton_method(:processor_count, original_processor_count)
  end
end
