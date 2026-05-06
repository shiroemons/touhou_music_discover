# frozen_string_literal: true

module Admin
  class Action
    include ActiveModel::Model

    Field = Data.define(:name, :type, :required, :help)

    FIELD_DEFINITIONS = {
      'FetchAppleMusicAlbumById' => [
        Field.new(:album_id, :text, true, 'Apple MusicのアルバムIDを入力してください')
      ],
      'ImportTracksWithOriginalSongs' => [
        Field.new(:tsv_file, :file, true, nil)
      ]
    }.freeze

    MEMBER_ACTIONS = %w[UpdateYtmusicAlbumPayload].freeze

    attr_accessor :resource, :action_class_name

    def key
      action_class_name.underscore
    end

    def action_class
      require_dependency 'admin/actions'

      Admin::Actions.const_get(action_class_name, false)
    end

    def label
      I18n.t("admin.actions.#{key}.label", default: default_label)
    end

    def description
      I18n.t("admin.actions.#{key}.description", default: I18n.t('admin.actions.default_description'))
    end

    def fields
      FIELD_DEFINITIONS.fetch(action_class_name, [])
    end

    def member?
      MEMBER_ACTIONS.include?(action_class_name)
    end

    def collection?
      !member?
    end

    def run(fields: {}, record: nil)
      action = action_class.new
      attach_progress_recorder(action)
      payload = { fields: fields_for_action(fields, record) }

      if action.class.instance_method(:handle).parameters.any? { |type, _name| type == :keyrest }
        action.handle(**payload)
      else
        action.handle(payload)
      end

      Admin::ActionResult.from_response(action.response)
    rescue RestClient::TooManyRequests => e
      SpotifyRateLimit.record_from_error!(e, source: action_class_name)
      Rails.logger.error("[Admin::Action] #{action_class_name} was rate limited: #{e.class} - #{e.message}")
      Admin::ActionResult.new(status: :error, message: e.message)
    rescue StandardError => e
      Rails.logger.error("[Admin::Action] #{action_class_name} failed: #{e.class} - #{e.message}")
      Admin::ActionResult.new(status: :error, message: e.message)
    end

    private

    def default_label
      return action_class.action_name if action_class.respond_to?(:action_name) && action_class.action_name.present?

      action_class.name.demodulize.underscore.humanize
    rescue StandardError
      action_class_name.underscore.humanize
    end

    def fields_for_action(fields, record)
      action_fields = fields.with_indifferent_access
      action_fields[:avo_resource_ids] = [record.id] if record.present?
      action_fields
    end

    def attach_progress_recorder(action)
      return if Admin::ActionProgress.current.blank?

      %i[inform succeed warn error].each do |method_name|
        next unless action.respond_to?(method_name)

        original_method = action.method(method_name)
        action.define_singleton_method(method_name) do |message = nil, *args, **kwargs, &block|
          Admin::ActionProgress.current&.record_message(message)
          original_method.call(message, *args, **kwargs, &block)
        end
      end
    end
  end
end
