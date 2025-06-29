# frozen_string_literal: true

require 'ostruct'
require 'active_support/core_ext/string/inflections'

module AppleMusic
  class Response
    attr_reader :body

    def initialize(body)
      @body = body
    end

    def data
      body['data']
    end

    def results
      result_data = body.dig('results', resource_type)
      return nil unless result_data

      if result_data.is_a?(Hash) && result_data['data']
        convert_to_objects(result_data['data'])
      else
        convert_to_objects(result_data)
      end
    end

    def first
      object_data = data.is_a?(Array) ? data.first : data
      convert_to_object(object_data)
    end

    def items
      array_data = data || []
      convert_to_objects(array_data)
    end

    def next_page?
      body['next'].present?
    end

    def next_url
      body['next']
    end

    private

    def convert_to_objects(array_data)
      return [] unless array_data.is_a?(Array)

      array_data.map { |item| convert_to_object(item) }
    end

    def convert_to_object(data)
      return nil unless data.is_a?(Hash)

      object = OpenStruct.new(data['id'] ? { id: data['id'] } : {})

      data['attributes']&.each do |key, value|
        object.send("#{key.underscore}=", value)
      end

      data['relationships']&.each do |key, value|
        object.send("#{key.underscore}=", value)
      end

      # Add as_json method to the object
      object.define_singleton_method(:as_json) do |_options = {}|
        data
      end

      object
    end

    def resource_type
      # Determine resource type from response structure
      return 'albums' if body.dig('results', 'albums')
      return 'artists' if body.dig('results', 'artists')
      return 'songs' if body.dig('results', 'songs')
      return 'playlists' if body.dig('results', 'playlists')

      nil
    end
  end
end
