# frozen_string_literal: true

class YtmusicAlbumResource < Avo::BaseResource
  self.title = :name
  self.description = 'YouTube Music アルバム'
  self.includes = [:ytmusic_tracks, { album: :circles }]
  self.record_selector = false
  self.search_query = lambda {
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
  field :release_year, as: :text, sortable: true, readonly: true
  field :total_tracks, as: :number, sortable: true, readonly: true
  field :track_count_check, as: :boolean, hide_on: [:forms] do |model|
    model.total_tracks == model.ytmusic_tracks.count
  end
  field :browse_id, as: :text, required: true
  field :url, as: :text, format_using: ->(url) { link_to(url, url, target: '_blank', rel: 'noopener') if url.present? }, hide_on: [:forms]
  field :playlist_url, as: :text, format_using: ->(url) { link_to(url, url, target: '_blank', rel: 'noopener') if url.present? }, hide_on: [:forms]

  field :ytmusic_tracks, as: :has_many, searchable: true
end
