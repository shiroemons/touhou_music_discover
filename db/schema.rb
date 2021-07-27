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

ActiveRecord::Schema.define(version: 2021_07_26_172438) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "pgcrypto"
  enable_extension "plpgsql"

  create_table "albums", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "jan_code", null: false
    t.boolean "is_touhou", default: true, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["jan_code"], name: "index_albums_on_jan_code", unique: true
  end

  create_table "master_artists", force: :cascade do |t|
    t.string "name", null: false
    t.string "key", default: "", null: false
    t.string "streaming_type", default: "", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "original_songs", primary_key: "code", id: :string, force: :cascade do |t|
    t.string "original_code", null: false
    t.string "title", null: false
    t.string "composer", default: "", null: false
    t.integer "track_number", null: false
    t.boolean "is_duplicate", default: false, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["code"], name: "index_original_songs_on_code", unique: true
    t.index ["original_code"], name: "index_original_songs_on_original_code"
  end

  create_table "originals", primary_key: "code", id: :string, force: :cascade do |t|
    t.string "title", null: false
    t.string "short_title", null: false
    t.string "original_type", null: false
    t.float "series_order", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "spotify_albums", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "album_id", null: false
    t.string "spotify_id", null: false
    t.string "album_type", null: false
    t.string "name", null: false
    t.string "label", null: false
    t.string "url"
    t.date "release_date"
    t.integer "total_tracks"
    t.boolean "is_touhou", default: true, null: false
    t.jsonb "payload"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["album_id"], name: "index_spotify_albums_on_album_id"
  end

  create_table "spotify_artists", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "spotify_id", null: false
    t.string "name", null: false
    t.string "url"
    t.integer "follower_count"
    t.jsonb "payload"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "spotify_tracks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "album_id", null: false
    t.uuid "track_id", null: false
    t.uuid "spotify_album_id", null: false
    t.string "spotify_id", null: false
    t.string "name", null: false
    t.string "label", null: false
    t.string "url"
    t.date "release_date"
    t.integer "disc_number"
    t.integer "track_number"
    t.integer "duration_ms"
    t.boolean "is_touhou", default: true, null: false
    t.jsonb "payload"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["album_id"], name: "index_spotify_tracks_on_album_id"
    t.index ["spotify_album_id"], name: "index_spotify_tracks_on_spotify_album_id"
    t.index ["track_id"], name: "index_spotify_tracks_on_track_id"
  end

  create_table "tracks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "isrc", null: false
    t.boolean "is_touhou", default: true, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["isrc"], name: "index_tracks_on_isrc", unique: true
  end

  add_foreign_key "spotify_albums", "albums"
  add_foreign_key "spotify_tracks", "albums"
  add_foreign_key "spotify_tracks", "spotify_albums"
  add_foreign_key "spotify_tracks", "tracks"
end
