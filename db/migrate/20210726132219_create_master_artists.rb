# frozen_string_literal: true

class CreateMasterArtists < ActiveRecord::Migration[6.1]
  def change
    create_table :master_artists do |t|
      t.string :name, null: false
      t.string :key, null: false, default: ''
      t.string :streaming_type, null: false, default: ''

      t.timestamps
    end
  end
end
