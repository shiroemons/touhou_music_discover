# frozen_string_literal: true

class CreateAlbums < ActiveRecord::Migration[6.1]
  def change
    create_table :albums, id: :uuid do |t|
      t.string :jan_code, null: false, index: { unique: true }

      t.timestamps
    end
  end
end
