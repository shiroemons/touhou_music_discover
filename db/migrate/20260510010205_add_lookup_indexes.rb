# frozen_string_literal: true

class AddLookupIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :circles_albums, :album_id, if_not_exists: true, algorithm: :concurrently

    add_index :spotify_albums, :spotify_id, if_not_exists: true, algorithm: :concurrently
    add_index :spotify_tracks, :spotify_id, if_not_exists: true, algorithm: :concurrently

    add_index :apple_music_albums, :apple_music_id, if_not_exists: true, algorithm: :concurrently
    add_index :apple_music_tracks, :apple_music_id, if_not_exists: true, algorithm: :concurrently

    add_index :line_music_albums, :line_music_id, if_not_exists: true, algorithm: :concurrently
    add_index :line_music_tracks, :line_music_id, if_not_exists: true, algorithm: :concurrently

    add_index :ytmusic_albums, :browse_id, if_not_exists: true, algorithm: :concurrently
    add_index :ytmusic_tracks, :video_id, if_not_exists: true, algorithm: :concurrently

    add_index :users, %i[provider uid], unique: true, if_not_exists: true, algorithm: :concurrently
  end
end
