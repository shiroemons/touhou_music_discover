# frozen_string_literal: true

class AppleMusicAlbumsToAlgoliaPresenter < Presenter
  ORIGINAL_TYPE = {
    windows: '01. Windows作品',
    pc98: '02. PC-98作品',
    zuns_music_collection: "03. ZUN's Music Collection",
    akyus_untouched_score: "04. 幺樂団の歴史　～ Akyu's Untouched Score",
    commercial_books: '05. 商業書籍',
    other: '06. その他'
  }.freeze

  def as_json(*)
    @object&.filter_map { |o| album_object(o) } || []
  end

  private

  def album_object(album)
    return nil if album.apple_music_album.nil?
    return nil unless album.is_touhou

    {
      objectID: album.id,
      jan: album.jan_code,
      name: album.apple_music_album_name,
      circles: album.circles&.map do |circle|
        {
          name: circle['name']
        }
      end || [],
      total_tracks: album.apple_music_album_total_tracks,
      url: album.apple_music_album_url,
      artists: [
        {
          name: album.apple_music_album_payload.dig('attributes', 'artist_name')
        }
      ],
      copyrights: [
        {
          text: album.apple_music_album_payload.dig('attributes', 'copyright')
        }
      ],
      image_url: album.apple_music_album_payload&.dig('attributes', 'artwork', 'url')&.sub('{w}x{h}', '500x500').presence || '',
      release_date: album.apple_music_album_release_date,
      tracks: track_objects(album.apple_music_tracks.sort_by { [it.disc_number, it.track_number] })
    }
  end

  def track_objects(apple_music_tracks)
    apple_music_tracks&.map { track_object(it) } || []
  end

  def track_object(apple_music_track)
    {
      isrc: apple_music_track.isrc,
      name: apple_music_track.name,
      is_touhou: apple_music_track.is_touhou,
      url: apple_music_track.url,
      disc_number: apple_music_track.disc_number,
      track_number: apple_music_track.track_number,
      duration_ms: apple_music_track.duration_ms,
      original_songs: original_song_objects(apple_music_track.track.original_songs)
    }
  end

  def original_song_objects(original_songs)
    original_songs.map { original_song_object(it) }
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
