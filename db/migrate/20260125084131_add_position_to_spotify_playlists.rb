class AddPositionToSpotifyPlaylists < ActiveRecord::Migration[8.0]
  def change
    add_column :spotify_playlists, :position, :integer, default: 0
  end
end
