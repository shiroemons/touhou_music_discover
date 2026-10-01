import 'settings.just'

# 外部から原曲紐付けデータを取得し紐付けを行う
fetch-touhou-music:
    devbox run import:fetch_touhou_music

# 原曲付きリストを読み込み原曲紐付けを行う
touhou-music-with-original-songs:
    devbox run import:touhou_music_with_original_songs
