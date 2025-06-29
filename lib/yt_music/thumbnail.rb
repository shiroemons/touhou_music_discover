# frozen_string_literal: true

module YTMusic
  class Thumbnail < Base
    attr_reader :url, :width, :height

    def initialize(content)
      @url = content['url']
      @width = content['width']
      @height = content['height']
      super()
    end
  end
end
