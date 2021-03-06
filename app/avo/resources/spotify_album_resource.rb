# frozen_string_literal: true

class SpotifyAlbumResource < Avo::BaseResource
  self.title = :name
  self.description = 'Spotify アルバム'
  self.includes = [:spotify_tracks, { album: :circles }]
  self.record_selector = false
  self.search_query = lambda { |params:|
    scope.ransack(name_cont: params[:q], album_circles_name_cont: params[:q], m: 'or').result(distinct: false)
  }

  field :image_url, as: :external_image, name: 'image', hide_on: [:forms], as_avatar: :rounded
  field :album, as: :belongs_to, name: 'jan code', searchable: true
  field :id, as: :id, hide_on: [:index]
  field :circle_name, as: :text, hide_on: [:forms]
  field :name, as: :text, sortable: true, readonly: true
  field :complex_name, as: :text, hide_on: :all, as_label: true do |model|
    "[#{model.circle_name}] #{model.name}"
  end
  field :album_type, as: :text, hide_on: [:index], readonly: true
  field :label, as: :text, hide_on: [:index], readonly: true
  field :release_date, as: :date, format: '%Y-%m-%d', sortable: true, readonly: true
  field :total_tracks, as: :number, sortable: true, readonly: true
  field :spotify_id, as: :text, required: true
  field :url, as: :text, format_using: ->(url) { link_to(url, url, target: '_blank', rel: 'noopener') if url.present? }, hide_on: [:forms]

  field :spotify_tracks, as: :has_many, searchable: true
end
