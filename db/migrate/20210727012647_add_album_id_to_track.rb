# frozen_string_literal: true

class AddAlbumIdToTrack < ActiveRecord::Migration[6.1]
  def change
    add_reference :tracks, :album, type: :uuid, foreign_key: true
  end
end
