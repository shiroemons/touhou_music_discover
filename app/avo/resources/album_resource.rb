# frozen_string_literal: true

class AlbumResource < Avo::BaseResource
  self.title = :jan_code
  self.translation_key = 'avo.resource_translations.album'
  self.search_query_help = 'JANコード、Spotify、Apple Music、LINE MUSIC、YouTube Musicのアルバム名で検索'
  self.includes = %i[circles
                     tracks
                     apple_music_album
                     apple_music_tracks
                     line_music_album
                     spotify_album
                     spotify_tracks
                     ytmusic_album
                     ytmusic_tracks]
  self.record_selector = false
  self.search_query = lambda {
    scope.ransack(
      jan_code_cont: params[:q],
      apple_music_album_name_cont: params[:q],
      line_music_album_name_cont: params[:q],
      spotify_album_name_cont: params[:q],
      ytmusic_album_name_cont: params[:q],
      m: 'or'
    ).result(distinct: false)
  }

  field :id, as: :id, hide_on: [:index]
  field :jan_code, as: :text, sortable: true
  field :is_touhou, as: :text, name: 'touhou', only_on: [:index], format_using: -> { value.present? ? '✅' : '' }, index_text_align: :center
  field :complex_name, as: :text, name: 'アルバム名', only_on: [:index] do |model|
    # 最初に見つかったアルバム名を使用
    name = model.spotify_album&.name ||
           model.apple_music_album&.name ||
           model.line_music_album&.name ||
           model.ytmusic_album&.name

    # 利用可能なサービスを示すアイコン的な表記
    services = []
    services << 'S' if model.spotify_album&.name.present?
    services << 'A' if model.apple_music_album&.name.present?
    services << 'L' if model.line_music_album&.name.present?
    services << 'Y' if model.ytmusic_album&.name.present?

    if name
      services.any? ? "#{name} [#{services.join('/')}] (JAN: #{model.jan_code})" : "#{name} (JAN: #{model.jan_code})"
    else
      "JAN: #{model.jan_code}"
    end
  end
  field :circle_name, as: :text, hide_on: [:forms]

  field :circles, as: :has_many, through: :circles_albums, searchable: true
  field :tracks, as: :has_many, searchable: true

  field :apple_music_album, as: :has_one, searchable: true
  field :apple_music_tracks, as: :has_many, searchable: true
  field :line_music_album, as: :has_one, searchable: true
  field :line_music_tracks, as: :has_many, searchable: true
  field :spotify_album, as: :has_one, searchable: true
  field :spotify_tracks, as: :has_many, searchable: true
  field :ytmusic_album, as: :has_one, searchable: true
  field :ytmusic_tracks, as: :has_many, searchable: true

  action BulkRetrieval
  action ChangeTouhouFlag
  action SetCircles

  filter NotDeliveredFilter
end
