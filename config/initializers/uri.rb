# frozen_string_literal: true

module URI
  module Escape
    def encode_www_form_component(str)
      uri = URI(str)
      "#{uri.scheme}://#{uri.host}#{uri.path}" + URI.encode_www_form_component(uri.query)
    rescue StandardError
      URI.encode_www_form_component(str)
    end
    alias encode encode_www_form_component
  end
  extend Escape
end
