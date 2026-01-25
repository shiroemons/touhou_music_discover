# frozen_string_literal: true

class SpotifyPlaylistResource < Avo::BaseResource
  self.title = :name
  self.translation_key = 'avo.resource_translations.spotify_playlist'
  self.includes = [:original_song]
  self.record_selector = false
  self.search_query = lambda {
    scope.ransack(name_cont: params[:q], original_song_code_cont: params[:q], m: 'or').result(distinct: false)
  }

  field :id, as: :id, hide_on: [:index]
  field :spotify_id, as: :text, readonly: true
  field :spotify_user_id, as: :text, readonly: true, hide_on: [:index]
  field :name, as: :text, sortable: true
  field :total, as: :number, sortable: true, readonly: true
  field :followers, as: :number, sortable: true, readonly: true
  field :spotify_url, as: :text, format_using: -> { link_to(value, value, target: '_blank', rel: 'noopener') if value.present? }, hide_on: [:forms]
  field :original_song_code, as: :text, hide_on: [:index]
  field :synced_at, as: :date_time, sortable: true, readonly: true
  field :created_at, as: :date_time, sortable: true, readonly: true, hide_on: [:index]
  field :updated_at, as: :date_time, sortable: true, readonly: true, hide_on: [:index]

  field :original_song, as: :belongs_to, searchable: true
end
