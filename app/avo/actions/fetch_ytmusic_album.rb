# frozen_string_literal: true

class FetchYtmusicAlbum < Avo::BaseAction
  self.name = 'Fetch ytmusic album'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    Album.includes(:spotify_album, :apple_music_album).missing_ytmusic_album.order(:jan_code).find_each do |album|
      sleep(0.2) # API呼び出し等のレート制限に配慮
      process_album_with_spotify(album)
      process_album_with_apple_music(album) if album.apple_music_album.present?
    end

    update_ytmusic_album_urls

    succeed 'Done!'
    reload
  end

  def process_album_with_spotify(album)
    s_album = album.spotify_album
    return if s_album.blank?

    browse_id = YtmusicAlbum::JAN_TO_ALBUM_BROWSE_IDS[album.jan_code]
    return if browse_id && YtmusicAlbum.find_and_save(browse_id, s_album)

    spotify_artist_names = s_album.payload['artists'].filter { _1['name'] != 'ZUN' }.map { _1['name'] }.join(' ')
    normalize_and_search_ytmusic(s_album, spotify_artist_names)
  end

  def process_album_with_apple_music(album)
    am_album = album.apple_music_album
    am_album_name = am_album.name.gsub(/(-|─|☆|■|≒|⇔)/, '')
    artist_name = am_album.artist_name
    query = "#{am_album_name} #{artist_name}"
    return if YtmusicAlbum.search_and_save(query, am_album)

    # Apple Musicアルバム名の様々なバリエーションで検索
    [am_album_name, am_album_name.sub(/ [(|\[].*[)|\]]\z/, ''), am_album.name, am_album.name.sub(' - EP', '')].each do |q|
      return if YtmusicAlbum.search_and_save(q, am_album)
    end
  end

  def normalize_and_search_ytmusic(s_album, artist_names)
    queries = [
      [s_album.name.unicode_normalize, artist_names],
      [s_album.name.unicode_normalize.gsub(/( -|─|☆|■|≒|⇔)/, ' ')
              .gsub(/\p{In_Halfwidth_and_Fullwidth_Forms}+/) { |str| str.unicode_normalize(:nfkd) }
              .gsub(/ [(|（\[].*[)|）\]]/, '')
              .tr('０-９', '0-9').strip, artist_names]
    ]
    queries << [s_album.name, ''] if s_album.name.unicode_normalize.include?('【睡眠用】東方ピアノ癒やし子守唄')
    queries.each do |name, names|
      query = "#{name} #{names}".strip
      return if YtmusicAlbum.search_and_save(query, s_album)
    end
  end

  def update_ytmusic_album_urls
    ytmusic_album_ids = YtmusicAlbum.where(url: nil).pluck(:id)
    batch_size = 1000
    ytmusic_album_ids.each_slice(batch_size) do |ids|
      YtmusicAlbum.where(id: ids).then do |records|
        Parallel.each(records, in_processes: 7) do |ytmusic_album|
          album = YTMusic::Album.find(ytmusic_album.browse_id)
          url = "https://music.youtube.com/browse/#{ytmusic_album.browse_id}"
          ytmusic_album.update_album(album, url) if album
        end
      end
    end
  end
end
