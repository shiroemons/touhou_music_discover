# frozen_string_literal: true

class CreateTracksOriginalSongs < ActiveRecord::Migration[6.1]
  def change
    create_table :tracks_original_songs, id: :uuid do |t|
      t.references :track, type: :uuid, null: false, foreign_key: true
      t.string :original_song_code, null: false, index: true

      t.timestamps
    end
    add_index :tracks_original_songs, %i[track_id original_song_code], unique: true
  end
end
