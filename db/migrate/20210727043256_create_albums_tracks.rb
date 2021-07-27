# frozen_string_literal: true

class CreateAlbumsTracks < ActiveRecord::Migration[6.1]
  def change
    create_table :albums_tracks, id: :uuid do |t|
      t.references :album, type: :uuid, index: false, null: false, foreign_key: true
      t.references :track, type: :uuid, index: false, null: false, foreign_key: true
      t.timestamps
    end
    add_index :albums_tracks, %i[album_id track_id], unique: true
  end
end
