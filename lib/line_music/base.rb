# frozen_string_literal: true

module LineMusic
  class Base
    class << self
      def find(id, type)
        type_class = LineMusic.const_get(type.singularize.capitalize)
        path = "#{type}/#{id}.v1"
        response = LineMusic.get path
        result = response.body.dig('response', 'result')

        case result[type]
        when Hash
          type_class.new result[type]
        when Array
          result[type].map { |t| type_class.new t }.first
        end
      end

      def search(query, type, start: 1, display: 100, sort: 'POPULAR')
        query = CGI.escape query
        path = "search/#{type}s.v1?query=#{query}&start=#{start}&display=#{display}&sort=#{sort}"
        response = LineMusic.get path

        type_class = LineMusic.const_get(type.singularize.capitalize)
        result = response.body.dig('response', 'result', "#{type}s")&.map { |t| type_class.new t } || []

        insert_total(result, type, response.body)
        result
      end

      def insert_total(result, type, body)
        result.instance_eval do
          @total = body['response']['result']["#{type}TotalCount"]

          define_singleton_method :total do
            @total
          end
        end
      end
    end
  end
end
