# frozen_string_literal: true

class LineMusicAlbumsToAlgoliaPresenter < Presenter
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
    return nil if album.line_music_album.nil?
    return nil unless album.is_touhou

    {
      objectID: album.id,
      jan: album.jan_code,
      name: album.line_music_album_name,
      circles: album.circles&.map do |circle|
        {
          name: circle['name']
        }
      end || [],
      total_tracks: album.line_music_album_total_tracks,
      url: album.line_music_album_url,
      artists: album.line_music_album_payload&.dig('artists')&.map do |artist|
        {
          name: artist['artist_name'],
          url: "https://music.line.me/webapp/artist/#{artist['artist_id']}"
        }
      end,
      image_url: album.line_music_album_payload&.dig('image_url').presence || '',
      release_date: album.line_music_album_release_date,
      tracks: track_objects(album.line_music_tracks.sort_by { [_1.disc_number, _1.track_number] })
    }
  end

  def track_objects(line_music_tracks)
    line_music_tracks&.map { track_object(_1) } || []
  end

  def track_object(line_music_track)
    {
      isrc: line_music_track.isrc,
      name: line_music_track.name,
      is_touhou: line_music_track.is_touhou,
      url: line_music_track.url,
      disc_number: line_music_track.disc_number,
      track_number: line_music_track.track_number,
      original_songs: original_song_objects(line_music_track.track.original_songs)
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
