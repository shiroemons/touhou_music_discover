# frozen_string_literal: true

class CreateTracks < ActiveRecord::Migration[6.1]
  def change
    create_table :tracks, id: :uuid do |t|
      t.string :isrc, null: false, index: { unique: true }
      t.boolean :is_touhou, null: false, default: true

      t.timestamps
    end
  end
end
