import 'settings.just'

# 原曲付きリストを出力
touhou-music-with-original-songs:
    devbox run export:touhou_music_with_original_songs

# 東方同人音楽流通 配信曲リスト出力
touhou-music:
    devbox run export:touhou_music

# 東方同人音楽流通 配信曲リストスリム版出力
touhou-music-slim:
    devbox run export:touhou_music_slim

# 東方同人音楽流通 配信アルバムリスト出力
touhou-music-album-only:
    devbox run export:touhou_music_album_only

# Algolia向けのJSON出力
for-algolia:
    devbox run export:for_algolia

# 東方サブスクランダム選曲アプリ用JSON出力
to-random-touhou-music:
    devbox run export:to_random_touhou_music

# 原曲紐づけがないアルバム一覧
missing-original-songs-albums:
    devbox run export:missing_original_songs_albums

# Spotifyエクスポート
spotify:
    devbox run export:spotify

# 全てのエクスポートファイルを一括出力
all: touhou-music-with-original-songs touhou-music touhou-music-slim touhou-music-album-only spotify missing-original-songs-albums
