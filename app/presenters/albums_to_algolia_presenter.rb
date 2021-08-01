# frozen_string_literal: true

class AlbumsToAlgoliaPresenter < Presenter
  ORIGINAL_TYPE = {
    windows: '01. Windows作品',
    pc98: '02. PC-98作品',
    zuns_music_collection: "03. ZUN's Music Collection",
    akyus_untouched_score: "04. 幺樂団の歴史　～ Akyu's Untouched Score",
    commercial_books: '05. 商業書籍',
    other: '06. その他'
  }.freeze

  def as_json(*)
    @object&.map { |o| album_object(o) }&.compact || []
  end

  private

  def album_object(album)
    return nil if album.spotify_album.nil?

    {
      objectID: album.id,
      jan: album.jan_code,
      is_touhou: album.is_touhou,
      name: album.spotify_album_name,
      total_tracks: album.spotify_album_total_tracks,
      url: album.spotify_album_url,
      uri: album.spotify_album_payload&.dig('uri'),
      artists: album.spotify_album_payload&.dig('artists')&.map do
        {
          name: _1['name'],
          uri: _1['uri'],
          url: _1.dig('external_urls', 'spotify')
        }
      end || [],
      copyrights: album.spotify_album_payload&.dig('copyrights')&.map do
        {
          text: _1['text'],
          type: _1['type']
        }
      end || [],
      images: album.spotify_album_payload&.dig('images')&.map do
        {
          url: _1['url'],
          width: _1['width'],
          height: _1['height']
        }
      end || [],
      tracks: track_objects(album.spotify_tracks)
    }
  end

  def track_objects(spotify_tracks)
    spotify_tracks&.map { track_object(_1) } || []
  end

  def track_object(spotify_track)
    {
      isrc: spotify_track.isrc,
      name: spotify_track.name,
      is_touhou: spotify_track.is_touhou,
      url: spotify_track.url,
      disc_number: spotify_track.disc_number,
      track_number: spotify_track.track_number,
      preview_url: spotify_track.payload&.dig('preview_url'),
      duration_ms: spotify_track.duration_ms,
      artists: spotify_track.payload&.dig('artists')&.map do |artist|
        {
          name: artist['name'],
          uri: artist['uri'],
          url: artist.dig('external_urls', 'spotify')
        }
      end,
      original_songs: original_song_objects(spotify_track.track.original_songs)
    }
  end

  def original_song_objects(original_songs)
    original_songs.map { original_song_object(_1) }
  end

  def original_song_object(original_song)
    {
      title: original_song.title,
      original: {
        title: original_song.original.title,
        short_title: original_song.original.short_title
      },
      'categories.lvl0': first_category(original_song.original),
      'categories.lvl1': second_category(original_song.original),
      'categories.lvl2': third_category(original_song)
    }
  end

  def first_category(original)
    ORIGINAL_TYPE[original.original_type.to_sym]
  end

  def second_category(original)
    "#{first_category(original)} > #{format('%#04.1f', original.series_order)}. #{original.short_title}"
  end

  def third_category(original_song)
    original = original_song.original
    "#{second_category(original)} > #{format('%02d', original_song.track_number)}. #{original_song.title}"
  end
end
