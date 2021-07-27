# frozen_string_literal: true

class AlbumsTrack < ApplicationRecord
  belongs_to :album
  belongs_to :track
end
