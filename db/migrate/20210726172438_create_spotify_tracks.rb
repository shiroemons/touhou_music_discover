# frozen_string_literal: true

class CreateSpotifyTracks < ActiveRecord::Migration[6.1]
  def change
    create_table :spotify_tracks, id: :uuid do |t|
      t.references :album, type: :uuid, null: false, foreign_key: true
      t.references :track, type: :uuid, null: false, foreign_key: true
      t.references :spotify_album, type: :uuid, null: false, foreign_key: true
      t.string :spotify_id, null: false
      t.string :name, null: false
      t.string :label, null: false
      t.string :url
      t.date :release_date
      t.integer :disc_number
      t.integer :track_number
      t.integer :duration_ms
      t.boolean :is_touhou, null: false, default: true
      t.jsonb :payload

      t.timestamps
    end
  end
end
