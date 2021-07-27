# frozen_string_literal: true

class CreateSpotifyArtists < ActiveRecord::Migration[6.1]
  def change
    create_table :spotify_artists, id: :uuid do |t|
      t.string :spotify_id, null: false
      t.string :name, null: false
      t.string :url
      t.integer :follower_count
      t.jsonb :payload

      t.timestamps
    end
  end
end
