# frozen_string_literal: true

class CreateYtmusicAlbums < ActiveRecord::Migration[7.0]
  def change
    create_table :ytmusic_albums, id: :uuid do |t|
      t.references :album, type: :uuid, null: false, foreign_key: true
      t.string :browse_id, null: false
      t.string :name, null: false
      t.string :url
      t.string :playlist_url
      t.string :release_year
      t.integer :total_tracks
      t.jsonb :payload

      t.timestamps
    end
  end
end
