# frozen_string_literal: true

class CreateLineMusicAlbums < ActiveRecord::Migration[7.0]
  def change
    create_table :line_music_albums, id: :uuid do |t|
      t.references :album, type: :uuid, null: false, foreign_key: true
      t.string :line_music_id, null: false
      t.string :name, null: false
      t.string :url
      t.date :release_date
      t.integer :total_tracks
      t.jsonb :payload

      t.timestamps
    end
  end
end
