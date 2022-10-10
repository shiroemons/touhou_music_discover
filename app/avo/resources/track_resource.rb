# frozen_string_literal: true

class TrackResource < Avo::BaseResource
  self.title = :isrc
  self.translation_key = 'avo.resource_translations.track'
  self.includes = [:original_songs]
  self.record_selector = false
  # self.search_query = -> do
  #   scope.ransack(id_eq: params[:q], m: "or").result(distinct: false)
  # end

  field :id, as: :id, hide_on: [:index]
  field :album, as: :belongs_to, searchable: true
  field :isrc, as: :text
  field :circle_name, as: :text, only_on: [:index]
  field :album_name, as: :text, only_on: [:index]
  field :name, as: :text, link_to_resource: true
  field :original_songs_count, as: :number, only_on: [:index], index_text_align: :right
  field :is_touhou, as: :text, name: 'touhou', only_on: [:index], format_using: ->(value) { value.present? ? '✅' : '' }, index_text_align: :center
  field :apple_music_tracks, as: :text, name: 'apple_music', only_on: [:index], format_using: ->(value) { value.present? ? '✅' : '' }, index_text_align: :center
  field :line_music_tracks, as: :text, name: 'ytmusic', only_on: [:index], format_using: ->(value) { value.present? ? '✅' : '' }, index_text_align: :center
  field :spotify_tracks, as: :text, name: 'spotify', only_on: [:index], format_using: ->(value) { value.present? ? '✅' : '' }, index_text_align: :center
  field :ytmusic_tracks, as: :text, name: 'line_music', only_on: [:index], format_using: ->(value) { value.present? ? '✅' : '' }, index_text_align: :center

  field :original_songs, as: :has_many, through: :tracks_original_songs, searchable: true, attach_scope: -> { query.non_duplicated }

  field :apple_music_tracks, as: :has_many, searchable: true
  field :line_music_tracks, as: :has_many, searchable: true
  field :spotify_tracks, as: :has_many, searchable: true
  field :ytmusic_tracks, as: :has_many, searchable: true

  action ExportMissingOriginalSongsTracks
  action ImportTracksWithOriginalSongs
  action ChangeTouhouFlag
end
