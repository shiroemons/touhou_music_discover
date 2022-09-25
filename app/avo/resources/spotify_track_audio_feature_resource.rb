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
  field :track, as: :belongs_to, name: 'isrc'
  field :spotify_track, as: :belongs_to
  field :loudness, as: :number, sortable: true
  field :tempo, as: :number, sortable: true
  field :time_signature, as: :number, sortable: true
  field :mode, as: :number, sortable: true
  field :key, as: :number, sortable: true
  field :valence, as: :number, sortable: true
  field :energy, as: :number, sortable: true
  field :danceability, as: :number, sortable: true
  field :acousticness, as: :number, sortable: true
  field :instrumentalness, as: :number, sortable: true
  field :liveness, as: :number, sortable: true
  field :speechiness, as: :number, sortable: true
end
