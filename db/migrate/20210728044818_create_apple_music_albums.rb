# frozen_string_literal: true

class CreateAppleMusicAlbums < ActiveRecord::Migration[6.1]
  def change
    create_table :apple_music_albums, id: :uuid do |t|
      t.references :album, type: :uuid, null: true, foreign_key: true
      t.string :apple_music_id, null: false
      t.string :name, null: false
      t.string :label, null: false
      t.string :url
      t.date :release_date
      t.integer :total_tracks
      t.jsonb :payload

      t.timestamps
    end
  end
end
