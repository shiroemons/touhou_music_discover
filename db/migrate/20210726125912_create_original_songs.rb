# frozen_string_literal: true

class CreateOriginalSongs < ActiveRecord::Migration[6.1]
  def change
    create_table :original_songs, id: false do |t|
      t.string :code, null: false, primary_key: true
      t.string :original_code, null: false
      t.string :title, null: false
      t.string :composer, null: false, default: ''
      t.integer :track_number, null: false
      t.boolean :is_duplicate, null: false, default: false

      t.timestamps
      t.index :code, unique: true
      t.index :original_code
    end
  end
end
