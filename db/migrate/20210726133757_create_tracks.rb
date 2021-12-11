# frozen_string_literal: true

class CreateTracks < ActiveRecord::Migration[6.1]
  def change
    create_table :tracks, id: :uuid do |t|
      t.string :jan_code, null: false
      t.string :isrc, null: false
      t.boolean :is_touhou, null: false, default: true

      t.timestamps
    end

    add_index :tracks, %i[jan_code isrc], unique: true
  end
end
