# frozen_string_literal: true

class NotDeliveredFilter < Avo::Filters::SelectFilter
  self.name = 'Not delivered filter'

  def apply(_request, query, value)
    case value
    when 'apple_music'
      query.missing_apple_music_album
    when 'spotify'
      query.missing_spotify_album
    when 'line_music'
      query.missing_line_music_album
    when 'ytmusic'
      query.missing_ytmusic_album
    else
      query
    end
  end

  def options
    {
      apple_music: 'Apple Music',
      spotify: 'Spotify',
      line_music: 'LINE MUSIC',
      ytmusic: 'YouTube Music'
    }
  end
end
