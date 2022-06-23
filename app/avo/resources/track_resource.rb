# frozen_string_literal: true

class TrackResource < Avo::BaseResource
  self.title = :isrc
  self.description = 'トラック'
  self.includes = [:original_songs]
  self.record_selector = false
  # self.search_query = ->(params:) do
  #   scope.ransack(id_eq: params[:q], m: "or").result(distinct: false)
  # end

  field :id, as: :id, hide_on: [:index]
  field :album, as: :belongs_to
  field :isrc, as: :text
  field :is_touhou, as: :boolean

  field :original_songs, as: :has_many, through: :tracks_original_songs

  field :apple_music_tracks, as: :has_many
  field :line_music_tracks, as: :has_many
  field :spotify_tracks, as: :has_many
  field :ytmusic_tracks, as: :has_many
end
