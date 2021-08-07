# frozen_string_literal: true

class CirclesAlbum < ApplicationRecord
  belongs_to :circle
  belongs_to :album
end
