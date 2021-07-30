class RemoveIsTouhouColumnToSpotify < ActiveRecord::Migration[6.1]
  def change
    remove_column :spotify_albums, :is_touhou, :boolean, null: false, default: true
    remove_column :spotify_tracks, :is_touhou, :boolean, null: false, default: true
  end
end
