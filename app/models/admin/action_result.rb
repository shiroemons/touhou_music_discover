# frozen_string_literal: true

module Admin
  class ActionResult
    include ActiveModel::Model

    attr_accessor :status, :message

    class << self
      def from_response(response)
        message = response&.fetch(:messages, nil)&.last
        new(
          status: message&.fetch(:type, nil) || :success,
          message: message&.fetch(:body, nil) || I18n.t('admin.actions.completed')
        )
      end
    end

    def success?
      status.to_sym == :success
    end
  end
end
