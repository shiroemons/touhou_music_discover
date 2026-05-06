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
      action_class_name.constantize
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
      action_class.name
    rescue StandardError
      action_class_name.underscore.humanize
    end

    def fields_for_action(fields, record)
      action_fields = fields.symbolize_keys
      action_fields[:avo_resource_ids] = [record.id] if record.present?
      action_fields
    end
  end
end
