# frozen_string_literal: true

class CreateSpotifyAlbums < ActiveRecord::Migration[6.1]
  def change
    create_table :spotify_albums, id: :uuid do |t|
      t.references :album, type: :uuid, null: false, foreign_key: true
      t.string :spotify_id, null: false
      t.string :album_type, null: false
      t.string :name, null: false
      t.string :label, null: false
      t.string :url
      t.date :release_date
      t.integer :total_tracks
      t.boolean :is_touhou, null: false, default: true
      t.jsonb :payload

      t.timestamps
    end
  end
end
