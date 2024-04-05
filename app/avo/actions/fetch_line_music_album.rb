# frozen_string_literal: true

class FetchLineMusicAlbum < Avo::BaseAction
  self.name = 'Fetch line music album'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    Album.includes(:spotify_album, :apple_music_album).missing_line_music_album.find_each do |album|
      process_spotify_albums(album.spotify_album) if album.spotify_album.present?
      process_apple_music_albums(album.apple_music_album) if album.apple_music_album.present?
    end

    update_line_music_album_info

    succeed 'Done!'
    reload
  end

  def process_spotify_albums(s_album)
    search_queries = [
      "#{s_album.name} #{s_album.payload['artists'].map { _1['name'] }.sort}",
      s_album.name,
      s_album.name.tr('〜~', '～'),
      s_album.name.unicode_normalize,
      s_album.name.sub(/ [(|\[].*[)|\]]\z/, '')
    ]

    search_queries.each do |query|
      return if LineMusicAlbum.search_and_save(query, s_album)
    end

    line_album_id = LineMusicAlbum::JAN_TO_ALBUM_IDS[s_album.album.jan_code]
    LineMusicAlbum.find_and_save(line_album_id, s_album) if line_album_id
  end

  def process_apple_music_albums(am_album)
    search_queries = [
      "#{am_album.name.sub(' - EP', '')} #{am_album.payload.dig('attributes', 'artist_name')}",
      am_album.name,
      am_album.name.sub(/ [(|\[].*[)|\]]\z/, '')
    ]

    search_queries.each do |query|
      return if LineMusicAlbum.search_and_save(query, am_album)
    end
  end

  def update_line_music_album_info
    lm_album_ids = LineMusicAlbum.where(url: nil).pluck(:id)
    batch_size = 1000
    lm_album_ids.each_slice(batch_size) do |ids|
      LineMusicAlbum.where(id: ids).then do |records|
        Parallel.each(records, in_processes: 7) do |line_music_album|
          lm_album = LineMusic::Album.find(line_music_album.line_music_id)
          next if lm_album.blank?

          line_music_album.update(
            name: lm_album.album_title,
            url: "https://music.line.me/webapp/album/#{line_music_album.line_music_id}",
            total_tracks: lm_album.track_total_count,
            release_date: lm_album.release_date,
            payload: lm_album.as_json
          )
        end
      end
    end
  end
end
