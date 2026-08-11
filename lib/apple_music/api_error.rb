# frozen_string_literal: true

module AppleMusic
  class ApiError < StandardError
    attr_reader :response

    def initialize(message, response = nil)
      super(message)
      @response = response
    end
  end
end
