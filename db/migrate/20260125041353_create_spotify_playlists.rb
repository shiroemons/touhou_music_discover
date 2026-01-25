class CreateSpotifyPlaylists < ActiveRecord::Migration[8.0]
  def change
    create_table :spotify_playlists, id: :uuid do |t|
      t.string :spotify_id, null: false
      t.string :spotify_user_id, null: false
      t.string :name, null: false
      t.integer :total, default: 0
      t.integer :followers, default: 0
      t.string :spotify_url
      t.string :original_song_code
      t.datetime :synced_at

      t.timestamps
    end

    add_index :spotify_playlists, :spotify_id, unique: true
    add_index :spotify_playlists, :spotify_user_id
    add_index :spotify_playlists, :original_song_code
  end
end
