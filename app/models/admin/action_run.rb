# frozen_string_literal: true

module Admin
  class ActionRun
    TTL = 12.hours
    KEY_PREFIX = 'admin:action_runs'

    class NotFound < StandardError; end

    class << self
      def create!(run_id:, resource_key:, action_key:, action_label:, redirect_path:)
        write(
          run_id,
          {
            'id' => run_id,
            'resource_key' => resource_key,
            'action_key' => action_key,
            'action_label' => action_label,
            'redirect_path' => redirect_path,
            'status' => 'processing',
            'current' => 0,
            'total' => 0,
            'message' => I18n.t('admin.actions.progress.started'),
            'result_message' => nil,
            'result_status' => nil,
            'started_at' => Time.current.iso8601,
            'completed_at' => nil
          }
        )
      end

      def find!(run_id)
        raw = redis.get(key(run_id))
        raise NotFound, "Admin action run not found: #{run_id}" if raw.blank?

        JSON.parse(raw)
      end

      def update!(run_id, attrs)
        data = find!(run_id).merge(stringify_attrs(attrs))
        write(run_id, data)
      end

      def complete!(run_id, result)
        status = result.status.to_sym == :error ? 'error' : 'completed'
        update!(
          run_id,
          status:,
          current: completion_current(run_id),
          message: result.message,
          result_message: result.message,
          result_status: result.status.to_s,
          completed_at: Time.current.iso8601
        )
      end

      def fail!(run_id, error)
        update!(
          run_id,
          status: 'error',
          message: error.message,
          result_message: error.message,
          result_status: 'error',
          completed_at: Time.current.iso8601
        )
      end

      private

      def completion_current(run_id)
        data = find!(run_id)
        total = data['total'].to_i
        total.positive? ? total : data['current'].to_i
      end

      def stringify_attrs(attrs)
        attrs.compact.transform_keys(&:to_s)
      end

      def write(run_id, data)
        redis.set(key(run_id), data.to_json, ex: TTL.to_i)
      end

      def key(run_id)
        "#{KEY_PREFIX}:#{run_id}"
      end

      def redis
        RedisPool.get
      end
    end
  end
end
