# frozen_string_literal: true

class TokenVerifier
  include ActiveSupport::Configurable
  include ActionController::RequestForgeryProtection

  def call(env)
    @request = ActionDispatch::Request.new(env.dup)
    raise OmniAuth::AuthenticityError unless verified_request?
  end

  private

  attr_reader :request

  delegate :params, :session, to: :request
end
