# frozen_string_literal: true

class CreateLineMusicTracks < ActiveRecord::Migration[7.0]
  def change
    create_table :line_music_tracks, id: :uuid do |t|
      t.references :album, type: :uuid, null: true, foreign_key: true
      t.references :track, type: :uuid, null: false, foreign_key: true
      t.references :line_music_album, type: :uuid, null: false, foreign_key: true
      t.string :line_music_id, null: false
      t.string :name, null: false
      t.string :url, null: false, default: ''
      t.integer :disc_number
      t.integer :track_number
      t.jsonb :payload

      t.timestamps
    end
  end
end
