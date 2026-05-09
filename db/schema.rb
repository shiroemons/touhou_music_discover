# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_10_010205) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "albums", id: :uuid, default: -> { "public.gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "is_touhou", default: true, null: false
    t.string "jan_code", null: false
    t.datetime "updated_at", null: false
    t.index ["jan_code"], name: "index_albums_on_jan_code", unique: true
  end

  create_table "apple_music_albums", id: :uuid, default: -> { "public.gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "album_id"
    t.string "apple_music_id", null: false
    t.datetime "created_at", null: false
    t.string "label", null: false
    t.string "name", null: false
    t.jsonb "payload"
    t.date "release_date"
    t.integer "total_tracks"
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["album_id"], name: "index_apple_music_albums_on_album_id"
    t.index ["apple_music_id"], name: "index_apple_music_albums_on_apple_music_id"
  end

  create_table "apple_music_artists", id: :uuid, default: -> { "public.gen_random_uuid()" }, force: :cascade do |t|
    t.string "apple_music_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.jsonb "payload"
    t.datetime "updated_at", null: false
    t.string "url"
  end

  create_table "apple_music_tracks", id: :uuid, default: -> { "public.gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "album_id"
    t.uuid "apple_music_album_id", null: false
    t.string "apple_music_id", null: false
    t.string "artist_name", default: "", null: false
    t.string "composer_name", default: "", null: false
    t.datetime "created_at", null: false
    t.integer "disc_number"
    t.integer "duration_ms"
    t.string "label", null: false
    t.string "name", null: false
    t.jsonb "payload"
    t.date "release_date"
    t.uuid "track_id", null: false
    t.integer "track_number"
    t.datetime "updated_at", null: false
    t.string "url", default: "", null: false
    t.index ["album_id"], name: "index_apple_music_tracks_on_album_id"
    t.index ["apple_music_album_id"], name: "index_apple_music_tracks_on_apple_music_album_id"
    t.index ["apple_music_id"], name: "index_apple_music_tracks_on_apple_music_id"
    t.index ["track_id"], name: "index_apple_music_tracks_on_track_id"
  end

  create_table "circles", id: :uuid, default: -> { "public.gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_circles_on_name", unique: true
  end

  create_table "circles_albums", id: :uuid, default: -> { "public.gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "album_id", null: false
    t.uuid "circle_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["album_id"], name: "index_circles_albums_on_album_id"
    t.index ["circle_id", "album_id"], name: "index_circles_albums_on_circle_id_and_album_id", unique: true
  end

  create_table "line_music_albums", id: :uuid, default: -> { "public.gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "album_id", null: false
    t.datetime "created_at", null: false
    t.string "line_music_id", null: false
    t.string "name", null: false
    t.jsonb "payload"
    t.date "release_date"
    t.integer "total_tracks"
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["album_id"], name: "index_line_music_albums_on_album_id"
    t.index ["line_music_id"], name: "index_line_music_albums_on_line_music_id"
  end

  create_table "line_music_tracks", id: :uuid, default: -> { "public.gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "album_id"
    t.datetime "created_at", null: false
    t.integer "disc_number"
    t.uuid "line_music_album_id", null: false
    t.string "line_music_id", null: false
    t.string "name", null: false
    t.jsonb "payload"
    t.uuid "track_id", null: false
    t.integer "track_number"
    t.datetime "updated_at", null: false
    t.string "url", default: "", null: false
    t.index ["album_id"], name: "index_line_music_tracks_on_album_id"
    t.index ["line_music_album_id"], name: "index_line_music_tracks_on_line_music_album_id"
    t.index ["line_music_id"], name: "index_line_music_tracks_on_line_music_id"
    t.index ["track_id"], name: "index_line_music_tracks_on_track_id"
  end

  create_table "master_artists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", default: "", null: false
    t.string "name", null: false
    t.string "streaming_type", default: "", null: false
    t.datetime "updated_at", null: false
  end

  create_table "original_songs", primary_key: "code", id: :string, force: :cascade do |t|
    t.string "composer", default: "", null: false
    t.datetime "created_at", null: false
    t.boolean "is_duplicate", default: false, null: false
    t.string "original_code", null: false
    t.string "title", null: false
    t.integer "track_number", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_original_songs_on_code", unique: true
    t.index ["original_code"], name: "index_original_songs_on_original_code"
  end

  create_table "originals", primary_key: "code", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "original_type", null: false
    t.float "series_order", null: false
    t.string "short_title", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
  end

  create_table "spotify_albums", id: :uuid, default: -> { "public.gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.uuid "album_id", null: false
    t.string "album_type", null: false
    t.datetime "created_at", null: false
    t.string "label", null: false
    t.string "name", null: false
    t.jsonb "payload"
    t.date "release_date"
    t.string "spotify_id", null: false
    t.integer "total_tracks"
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["album_id"], name: "index_spotify_albums_on_active_album_id_unique", unique: true, where: "active"
    t.index ["album_id"], name: "index_spotify_albums_on_album_id"
    t.index ["spotify_id"], name: "index_spotify_albums_on_spotify_id"
  end

  create_table "spotify_artists", id: :uuid, default: -> { "public.gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "follower_count"
    t.string "name", null: false
    t.jsonb "payload"
    t.string "spotify_id", null: false
    t.datetime "updated_at", null: false
    t.string "url"
  end

  create_table "spotify_playlists", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "followers", default: 0
    t.string "name", null: false
    t.string "original_song_code"
    t.integer "position", default: 0
    t.string "spotify_id", null: false
    t.string "spotify_url"
    t.string "spotify_user_id", null: false
    t.datetime "synced_at"
    t.integer "total", default: 0
    t.datetime "updated_at", null: false
    t.index ["original_song_code"], name: "index_spotify_playlists_on_original_song_code"
    t.index ["spotify_id"], name: "index_spotify_playlists_on_spotify_id", unique: true
    t.index ["spotify_user_id"], name: "index_spotify_playlists_on_spotify_user_id"
  end

  create_table "spotify_track_audio_features", id: :uuid, default: -> { "public.gen_random_uuid()" }, force: :cascade do |t|
    t.float "acousticness", null: false
    t.string "analysis_url", default: "", null: false
    t.datetime "created_at", null: false
    t.float "danceability", null: false
    t.integer "duration_ms", null: false
    t.float "energy", null: false
    t.float "instrumentalness", null: false
    t.integer "key", null: false
    t.float "liveness", null: false
    t.float "loudness", null: false
    t.integer "mode", null: false
    t.jsonb "payload"
    t.float "speechiness", null: false
    t.string "spotify_id", null: false
    t.uuid "spotify_track_id", null: false
    t.float "tempo", null: false
    t.integer "time_signature", null: false
    t.uuid "track_id", null: false
    t.datetime "updated_at", null: false
    t.float "valence", null: false
    t.index ["spotify_track_id"], name: "index_spotify_track_audio_features_on_spotify_track_id"
    t.index ["track_id"], name: "index_spotify_track_audio_features_on_track_id"
  end

  create_table "spotify_tracks", id: :uuid, default: -> { "public.gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "album_id", null: false
    t.datetime "created_at", null: false
    t.integer "disc_number"
    t.integer "duration_ms"
    t.string "label", null: false
    t.string "name", null: false
    t.jsonb "payload"
    t.date "release_date"
    t.uuid "spotify_album_id", null: false
    t.string "spotify_id", null: false
    t.uuid "track_id", null: false
    t.integer "track_number"
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["album_id"], name: "index_spotify_tracks_on_album_id"
    t.index ["spotify_album_id"], name: "index_spotify_tracks_on_spotify_album_id"
    t.index ["spotify_id"], name: "index_spotify_tracks_on_spotify_id"
    t.index ["track_id"], name: "index_spotify_tracks_on_track_id"
  end

  create_table "tracks", id: :uuid, default: -> { "public.gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "is_touhou", default: true, null: false
    t.string "isrc", null: false
    t.string "jan_code", null: false
    t.datetime "updated_at", null: false
    t.index ["jan_code", "isrc"], name: "index_tracks_on_jan_code_and_isrc", unique: true
  end

  create_table "tracks_original_songs", id: :uuid, default: -> { "public.gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "original_song_code", null: false
    t.uuid "track_id", null: false
    t.datetime "updated_at", null: false
    t.index ["original_song_code"], name: "index_tracks_original_songs_on_original_song_code"
    t.index ["track_id", "original_song_code"], name: "index_tracks_original_songs_on_track_id_and_original_song_code", unique: true
    t.index ["track_id"], name: "index_tracks_original_songs_on_track_id"
  end

  create_table "users", id: :uuid, default: -> { "public.gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description", default: "", null: false
    t.string "email", default: "", null: false
    t.string "image_url", default: "", null: false
    t.string "name", null: false
    t.string "nickname", default: "", null: false
    t.string "provider", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
  end

  create_table "ytmusic_albums", id: :uuid, default: -> { "public.gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "album_id", null: false
    t.string "browse_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.jsonb "payload"
    t.string "playlist_url"
    t.string "release_year"
    t.integer "total_tracks"
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["album_id"], name: "index_ytmusic_albums_on_album_id"
    t.index ["browse_id"], name: "index_ytmusic_albums_on_browse_id"
  end

  create_table "ytmusic_tracks", id: :uuid, default: -> { "public.gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "album_id"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.jsonb "payload"
    t.string "playlist_id", null: false
    t.uuid "track_id", null: false
    t.integer "track_number"
    t.datetime "updated_at", null: false
    t.string "url", default: "", null: false
    t.string "video_id", null: false
    t.uuid "ytmusic_album_id", null: false
    t.index ["album_id"], name: "index_ytmusic_tracks_on_album_id"
    t.index ["track_id"], name: "index_ytmusic_tracks_on_track_id"
    t.index ["video_id"], name: "index_ytmusic_tracks_on_video_id"
    t.index ["ytmusic_album_id"], name: "index_ytmusic_tracks_on_ytmusic_album_id"
  end

  add_foreign_key "apple_music_albums", "albums"
  add_foreign_key "apple_music_tracks", "albums"
  add_foreign_key "apple_music_tracks", "apple_music_albums"
  add_foreign_key "apple_music_tracks", "tracks"
  add_foreign_key "circles_albums", "albums"
  add_foreign_key "circles_albums", "circles"
  add_foreign_key "line_music_albums", "albums"
  add_foreign_key "line_music_tracks", "albums"
  add_foreign_key "line_music_tracks", "line_music_albums"
  add_foreign_key "line_music_tracks", "tracks"
  add_foreign_key "spotify_albums", "albums"
  add_foreign_key "spotify_track_audio_features", "spotify_tracks"
  add_foreign_key "spotify_track_audio_features", "tracks"
  add_foreign_key "spotify_tracks", "albums"
  add_foreign_key "spotify_tracks", "spotify_albums"
  add_foreign_key "spotify_tracks", "tracks"
  add_foreign_key "tracks_original_songs", "tracks"
  add_foreign_key "ytmusic_albums", "albums"
  add_foreign_key "ytmusic_tracks", "albums"
  add_foreign_key "ytmusic_tracks", "tracks"
  add_foreign_key "ytmusic_tracks", "ytmusic_albums"
end
