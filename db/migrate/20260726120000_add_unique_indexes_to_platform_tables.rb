# frozen_string_literal: true

class AddUniqueIndexesToPlatformTables < ActiveRecord::Migration[8.1]
  def up
    # apple_music_albums: 既存の非unique indexをunique indexに置き換え
    remove_index :apple_music_albums, :apple_music_id, name: 'index_apple_music_albums_on_apple_music_id'
    add_index :apple_music_albums, :apple_music_id, unique: true,
                                                    name: 'index_apple_music_albums_on_apple_music_id'

    # apple_music_tracks: 複合unique index（新規）
    add_index :apple_music_tracks, %i[apple_music_album_id apple_music_id], unique: true,
                                                                            name: 'index_apple_music_tracks_on_am_album_id_and_am_id'

    # spotify_tracks: 複合unique index（新規）
    add_index :spotify_tracks, %i[spotify_album_id spotify_id], unique: true,
                                                                name: 'index_spotify_tracks_on_spotify_album_id_and_spotify_id'

    # spotify_track_audio_features: 既存の非unique indexをunique indexに置き換え
    remove_index :spotify_track_audio_features, :spotify_track_id,
                 name: 'index_spotify_track_audio_features_on_spotify_track_id'
    add_index :spotify_track_audio_features, :spotify_track_id, unique: true,
                                                                name: 'index_spotify_track_audio_features_on_spotify_track_id'

    # line_music_albums: 複合unique index（新規、単独外部IDでのuniqueは不可のため複合）
    add_index :line_music_albums, %i[album_id line_music_id], unique: true,
                                                              name: 'index_line_music_albums_on_album_id_and_line_music_id'

    # line_music_tracks: 複合unique index（新規）
    add_index :line_music_tracks, %i[line_music_album_id line_music_id], unique: true,
                                                                         name: 'index_line_music_tracks_on_lm_album_id_and_lm_id'

    # ytmusic_albums: 複合unique index（新規、単独外部IDでのuniqueは不可のため複合）
    add_index :ytmusic_albums, %i[album_id browse_id], unique: true,
                                                       name: 'index_ytmusic_albums_on_album_id_and_browse_id'

    # ytmusic_tracks: 複合unique index（新規、video_idはディスク跨ぎ誤マッチのため使えない）
    add_index :ytmusic_tracks, %i[ytmusic_album_id track_id], unique: true,
                                                              name: 'index_ytmusic_tracks_on_ytmusic_album_id_and_track_id'

    # apple_music_artists: 新規unique index（既存index無し）
    add_index :apple_music_artists, :apple_music_id, unique: true,
                                                     name: 'index_apple_music_artists_on_apple_music_id'

    # spotify_artists: 新規unique index（既存index無し）
    add_index :spotify_artists, :spotify_id, unique: true,
                                             name: 'index_spotify_artists_on_spotify_id'
  end

  def down
    remove_index :spotify_artists, name: 'index_spotify_artists_on_spotify_id'
    remove_index :apple_music_artists, name: 'index_apple_music_artists_on_apple_music_id'
    remove_index :ytmusic_tracks, name: 'index_ytmusic_tracks_on_ytmusic_album_id_and_track_id'
    remove_index :ytmusic_albums, name: 'index_ytmusic_albums_on_album_id_and_browse_id'
    remove_index :line_music_tracks, name: 'index_line_music_tracks_on_lm_album_id_and_lm_id'
    remove_index :line_music_albums, name: 'index_line_music_albums_on_album_id_and_line_music_id'

    remove_index :spotify_track_audio_features,
                 name: 'index_spotify_track_audio_features_on_spotify_track_id'
    add_index :spotify_track_audio_features, :spotify_track_id,
              name: 'index_spotify_track_audio_features_on_spotify_track_id'

    remove_index :spotify_tracks, name: 'index_spotify_tracks_on_spotify_album_id_and_spotify_id'
    remove_index :apple_music_tracks, name: 'index_apple_music_tracks_on_am_album_id_and_am_id'

    remove_index :apple_music_albums, name: 'index_apple_music_albums_on_apple_music_id'
    add_index :apple_music_albums, :apple_music_id,
              name: 'index_apple_music_albums_on_apple_music_id'
  end
end
