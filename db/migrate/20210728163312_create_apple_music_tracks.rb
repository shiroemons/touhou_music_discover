# frozen_string_literal: true

class CreateAppleMusicTracks < ActiveRecord::Migration[6.1]
  def change
    create_table :apple_music_tracks, id: :uuid do |t|
      t.references :album, type: :uuid, null: true, foreign_key: true
      t.references :track, type: :uuid, null: false, foreign_key: true
      t.references :apple_music_album, type: :uuid, null: false, foreign_key: true
      t.string :apple_music_id, null: false
      t.string :name, null: false
      t.string :label, null: false
      t.string :artist_name, null: false, default: ''
      t.string :composer_name, null: false, default: ''
      t.string :url, null: false, default: ''
      t.date :release_date
      t.integer :disc_number
      t.integer :track_number
      t.integer :duration_ms
      t.jsonb :payload

      t.timestamps
    end
  end
end
