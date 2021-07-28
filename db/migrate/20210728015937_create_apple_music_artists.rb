# frozen_string_literal: true

class CreateAppleMusicArtists < ActiveRecord::Migration[6.1]
  def change
    create_table :apple_music_artists, id: :uuid do |t|
      t.string :apple_music_id, null: false
      t.string :name, null: false
      t.string :url
      t.jsonb :payload

      t.timestamps
    end
  end
end
