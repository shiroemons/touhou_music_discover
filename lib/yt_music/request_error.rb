# frozen_string_literal: true

module YtMusic
  class RequestError < StandardError
    attr_reader :status

    def initialize(status:, invalid_body: false)
      @status = status.to_i
      message = if invalid_body
                  "YouTube Music API returned an invalid response (HTTP #{@status}, expected a JSON object)"
                else
                  "YouTube Music API request failed (HTTP #{@status})"
                end
      super(message)
    end
  end
end
