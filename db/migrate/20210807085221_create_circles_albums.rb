# frozen_string_literal: true

class CreateCirclesAlbums < ActiveRecord::Migration[6.1]
  def change
    create_table :circles_albums, id: :uuid do |t|
      t.references :circle, type: :uuid, index: false, null: false, foreign_key: true
      t.references :album, type: :uuid, index: false, null: false, foreign_key: true
      t.timestamps
    end
    add_index :circles_albums, %i[circle_id album_id], unique: true
  end
end
