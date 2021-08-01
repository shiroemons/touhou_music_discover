# frozen_string_literal: true

class Presenter
  def initialize(object)
    @object = object
  end

  def as_json
    raise 'as_json called on parent.'
  end
end
