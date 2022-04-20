# frozen_string_literal: true

class CreateYtmusicTracks < ActiveRecord::Migration[7.0]
  def change
    create_table :ytmusic_tracks, id: :uuid do |t|
      t.references :album, type: :uuid, null: true, foreign_key: true
      t.references :track, type: :uuid, null: false, foreign_key: true
      t.references :ytmusic_album, type: :uuid, null: false, foreign_key: true
      t.string :video_id, null: false
      t.string :playlist_id, null: false
      t.string :name, null: false
      t.string :url, null: false, default: ''
      t.integer :track_number
      t.jsonb :payload

      t.timestamps
    end
  end
end
