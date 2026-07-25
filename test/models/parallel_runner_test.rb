# frozen_string_literal: true

require 'test_helper'

class ParallelRunnerTest < ActiveSupport::TestCase
  test 'resolves a Symbol worker key from WORKERS' do
    with_forced_workers(nil) do
      with_env('PARALLEL_WORKERS', nil) do
        assert_equal [7, Parallel.processor_count].min, ParallelRunner.effective_workers(:ytmusic)
        assert_equal [4, Parallel.processor_count].min, ParallelRunner.effective_workers(:line_music)
        assert_equal [3, Parallel.processor_count].min, ParallelRunner.effective_workers(:spotify)
      end
    end
  end

  test 'raises for an unknown Symbol worker key' do
    with_forced_workers(nil) do
      with_env('PARALLEL_WORKERS', nil) do
        assert_raises(KeyError) { ParallelRunner.effective_workers(:unknown_platform) }
      end
    end
  end

  test 'resolves an Integer worker count' do
    with_forced_workers(nil) do
      with_env('PARALLEL_WORKERS', nil) do
        assert_equal 2, ParallelRunner.effective_workers(2)
      end
    end
  end

  test 'caps the worker count at the processor count' do
    with_forced_workers(nil) do
      with_env('PARALLEL_WORKERS', nil) do
        assert_equal Parallel.processor_count, ParallelRunner.effective_workers(Parallel.processor_count + 100)
      end
    end
  end

  test 'PARALLEL_WORKERS overrides the per-call workers argument' do
    with_forced_workers(nil) do
      with_env('PARALLEL_WORKERS', '4') do
        assert_equal 4, ParallelRunner.effective_workers(:ytmusic)
      end
    end
  end

  test 'blank PARALLEL_WORKERS is ignored' do
    with_forced_workers(nil) do
      with_env('PARALLEL_WORKERS', '') do
        assert_equal [7, Parallel.processor_count].min, ParallelRunner.effective_workers(:ytmusic)
      end
    end
  end

  test 'forced_workers takes precedence over PARALLEL_WORKERS and the workers argument' do
    with_forced_workers(2) do
      with_env('PARALLEL_WORKERS', '4') do
        assert_equal 2, ParallelRunner.effective_workers(:ytmusic)
      end
    end
  end

  test 'reset_forced_workers! clears the override' do
    with_forced_workers(3) do
      ParallelRunner.reset_forced_workers!

      assert_nil ParallelRunner.forced_workers
    end
  end

  test 'runs inline without forking when the effective worker count is 1' do
    visited = []

    # インラインで実行された場合のみ、呼び出し元のローカル変数への追記が見える。
    # fork していたら子プロセス側の変更は親に反映されない。
    ParallelRunner.each([1, 2, 3], workers: 1) { |item| visited << item }

    assert_equal [1, 2, 3], visited
  end

  test 'inline fallback passes item, index and result to the finish callback' do
    finished = []
    finish = ->(item, index, result) { finished << [item, index, result] }

    ParallelRunner.each([10, 20], workers: 1, finish:) { |item| item * 2 }

    assert_equal [[10, 0, 20], [20, 1, 40]], finished
  end

  test 'parallel path passes item, index and result to the finish callback' do
    mutex = Mutex.new
    finished = []
    finish = ->(item, index, result) { mutex.synchronize { finished << [item, index, result] } }

    with_forced_workers(nil) do
      with_env('PARALLEL_WORKERS', nil) do
        ParallelRunner.each([10, 20], workers: 2, mode: :threads, finish:) { |item| item * 2 }
      end
    end

    assert_equal [[10, 0, 20], [20, 1, 40]], finished.sort
  end

  test 'raises for an unknown mode' do
    with_forced_workers(nil) do
      with_env('PARALLEL_WORKERS', nil) do
        assert_raises(ArgumentError) do
          ParallelRunner.each([1, 2], workers: 2, mode: :fibers) { |item| item }
        end
      end
    end
  end

  private

  def with_forced_workers(value)
    previous = ParallelRunner.forced_workers
    ParallelRunner.forced_workers = value
    yield
  ensure
    ParallelRunner.forced_workers = previous
  end

  def with_env(key, value)
    previous = ENV.fetch(key, nil)
    ENV[key] = value
    yield
  ensure
    ENV[key] = previous
  end
end
