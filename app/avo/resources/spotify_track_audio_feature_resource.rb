# frozen_string_literal: true

class SpotifyTrackAudioFeatureResource < Avo::BaseResource
  self.title = :analysis_url
  self.description = 'Spotify トラックオーディオフィーチャー'
  self.includes = %i[track spotify_track]
  self.record_selector = false
  # self.search_query = -> do
  #   scope.ransack(id_eq: params[:q], m: "or").result(distinct: false)
  # end

  field :id, as: :id, hide_on: [:index]
  field :track, as: :belongs_to, name: 'isrc', hide_on: [:index], readonly: true
  field :spotify_track, as: :belongs_to, readonly: true
  field :loudness, as: :number, sortable: true, readonly: true
  field :tempo, as: :number, sortable: true, readonly: true
  field :time_signature, as: :number, sortable: true, readonly: true
  field :mode, as: :number, sortable: true, readonly: true
  field :key, as: :number, sortable: true, readonly: true
  field :valence, as: :number, sortable: true, readonly: true
  field :energy, as: :number, sortable: true, readonly: true
  field :danceability, as: :number, sortable: true, readonly: true
  field :acousticness, as: :number, sortable: true, readonly: true
  field :instrumentalness, as: :number, sortable: true, readonly: true
  field :liveness, as: :number, sortable: true, readonly: true
  field :speechiness, as: :number, sortable: true, readonly: true
end
