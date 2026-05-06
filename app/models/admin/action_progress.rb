# frozen_string_literal: true

module Admin
  class ActionProgress
    PROGRESS_PATTERN = %r{(?<current>\d+)\s*/\s*(?<total>\d+)}
    PERCENT_PATTERN = /Progress:\s*(?<percent>\d+(?:\.\d+)?)%/i

    class << self
      def with(progress)
        previous = Thread.current[:admin_action_progress]
        Thread.current[:admin_action_progress] = progress
        yield
      ensure
        Thread.current[:admin_action_progress] = previous
      end

      def current
        Thread.current[:admin_action_progress]
      end

      def start(total:, message: nil)
        current&.start(total:, message:)
      end

      def update(current:, total: nil, message: nil)
        self.current&.update(current:, total:, message:)
      end

      def advance(message: nil, by: 1)
        current&.advance(message:, by:)
      end
    end

    def initialize(run_id)
      @run_id = run_id
      @current = 0
      @total = 0
      @mutex = Mutex.new
    end

    def start(total:, message: nil)
      @mutex.synchronize do
        @current = 0
        @total = total.to_i
        persist(message:)
      end
    end

    def update(current:, total: nil, message: nil)
      @mutex.synchronize do
        @current = [current.to_i, @current].max
        @total = total.to_i if total.present?
        persist(message:)
      end
    end

    def advance(message: nil, by: 1)
      @mutex.synchronize do
        @current += by.to_i
        persist(message:)
      end
    end

    def record_message(message)
      text = message.to_s
      if (match = text.match(PROGRESS_PATTERN))
        update(current: match[:current], total: match[:total], message: text)
      elsif (match = text.match(PERCENT_PATTERN))
        percent = match[:percent].to_f
        update(current: percent, total: 100, message: text)
      elsif text.present?
        @mutex.synchronize { persist(message: text) }
      end
    end

    private

    def persist(message: nil)
      attrs = {
        current: @current,
        total: @total,
        message: message.presence,
        updated_at: Time.current.iso8601
      }
      Admin::ActionRun.update!(@run_id, attrs)
    end
  end
end
