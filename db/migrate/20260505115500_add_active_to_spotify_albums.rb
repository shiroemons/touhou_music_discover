# frozen_string_literal: true

class AddActiveToSpotifyAlbums < ActiveRecord::Migration[8.0]
  def change
    add_column :spotify_albums, :active, :boolean, null: false, default: true

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          WITH track_counts AS (
            SELECT spotify_album_id, COUNT(*) AS track_count
            FROM spotify_tracks
            GROUP BY spotify_album_id
          ),
          ranked AS (
            SELECT
              spotify_albums.id,
              ROW_NUMBER() OVER (
                PARTITION BY spotify_albums.album_id
                ORDER BY
                  CASE
                    WHEN jsonb_typeof(spotify_albums.payload->'available_markets') = 'array'
                      AND (spotify_albums.payload->'available_markets') ? 'JP'
                    THEN 1
                    ELSE 0
                  END DESC,
                  CASE
                    WHEN jsonb_typeof(spotify_albums.payload->'available_markets') = 'array'
                      AND jsonb_array_length(spotify_albums.payload->'available_markets') > 0
                    THEN 1
                    ELSE 0
                  END DESC,
                  CASE
                    WHEN COALESCE(track_counts.track_count, 0) >= COALESCE(spotify_albums.total_tracks, 0)
                    THEN 1
                    ELSE 0
                  END DESC,
                  COALESCE(track_counts.track_count, 0) DESC,
                  COALESCE(spotify_albums.total_tracks, 0) DESC,
                  spotify_albums.created_at DESC,
                  spotify_albums.id DESC
              ) AS position
            FROM spotify_albums
            LEFT JOIN track_counts ON track_counts.spotify_album_id = spotify_albums.id
          )
          UPDATE spotify_albums
          SET active = (ranked.position = 1)
          FROM ranked
          WHERE spotify_albums.id = ranked.id
        SQL
      end
    end

    add_index :spotify_albums,
              :album_id,
              unique: true,
              where: 'active',
              name: 'index_spotify_albums_on_active_album_id_unique'
  end
end
