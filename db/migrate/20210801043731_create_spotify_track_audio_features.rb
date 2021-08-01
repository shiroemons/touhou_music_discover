# frozen_string_literal: true

class CreateSpotifyTrackAudioFeatures < ActiveRecord::Migration[6.1]
  def change
    create_table :spotify_track_audio_features, id: :uuid do |t|
      t.references :track, type: :uuid, null: false, foreign_key: true
      t.references :spotify_track, type: :uuid, null: false, foreign_key: true
      t.string :spotify_id, null: false
      t.float :acousticness, null: false
      t.string :analysis_url, null: false, default: ''
      t.float :danceability, null: false
      t.integer :duration_ms, null: false
      t.float :energy, null: false
      t.float :instrumentalness, null: false
      t.integer :key, null: false
      t.float :liveness, null: false
      t.float :loudness, null: false
      t.integer :mode, null: false
      t.float :speechiness, null: false
      t.float :tempo, null: false
      t.integer :time_signature, null: false
      t.float :valence, null: false
      t.jsonb :payload

      t.timestamps
    end
  end
end
