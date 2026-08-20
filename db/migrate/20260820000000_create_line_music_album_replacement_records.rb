# frozen_string_literal: true

class CreateLineMusicAlbumReplacementRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :line_music_album_replacement_candidates, id: :uuid do |t|
      t.references :line_music_album, null: false, type: :uuid, foreign_key: true
      t.string :line_music_id, null: false
      t.string :name, null: false
      t.string :url
      t.date :release_date
      t.integer :total_tracks
      t.jsonb :payload
      t.string :status, null: false, default: 'pending'
      t.timestamps
    end

    add_index :line_music_album_replacement_candidates,
              %i[line_music_album_id line_music_id],
              unique: true,
              name: 'index_lm_replacement_candidates_on_album_and_lm_id'
    add_index :line_music_album_replacement_candidates, :status

    create_table :line_music_album_replacements, id: :uuid do |t|
      t.references :line_music_album, null: false, type: :uuid, foreign_key: true
      t.string :old_line_music_id, null: false
      t.string :new_line_music_id, null: false
      t.string :old_url
      t.string :new_url, null: false
      t.integer :old_total_tracks
      t.integer :new_total_tracks, null: false
      t.jsonb :before_snapshot, null: false, default: {}
      t.jsonb :after_snapshot, null: false, default: {}
      t.string :action_run_id
      t.timestamps
    end

    add_index :line_music_album_replacements, :old_line_music_id
    add_index :line_music_album_replacements, :new_line_music_id
    add_index :line_music_album_replacements, :action_run_id
  end
end
