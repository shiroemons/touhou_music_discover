# frozen_string_literal: true

class LineMusicAlbumResource < Avo::BaseResource
  self.title = :name
  self.translation_key = 'avo.resource_translations.line_music_album'
  self.includes = [:line_music_tracks, { album: :circles }]
  self.record_selector = false
  self.search_query = lambda {
    scope.ransack(name_cont: params[:q], album_circles_name_cont: params[:q], m: 'or').result(distinct: false)
  }

  self.default_view_type = :grid

  grid do
    cover :image_url, as: :external_image, is_image: true, link_to_resource: true
    title :name, as: :text, link_to_resource: true
    body :circle_name, as: :text
  end

  field :image_url, as: :external_image, name: 'image', hide_on: [:forms], as_avatar: :rounded
  field :album, as: :belongs_to, name: 'jan code', searchable: true
  field :id, as: :id, hide_on: [:index]
  field :circle_name, as: :text, hide_on: [:forms]
  field :name, as: :text, sortable: true, readonly: true
  field :complex_name, as: :text, hide_on: :all, as_label: true do |model|
    "[#{model.circle_name}] #{model.name}"
  end
  field :line_music_id, as: :text, required: true
  field :url, as: :text, format_using: -> { link_to(value, value, target: '_blank', rel: 'noopener') if value.present? }, hide_on: [:forms]
  field :release_date, as: :date, format: 'yyyy-LL-dd', readonly: true
  field :total_tracks, as: :number, readonly: true
  field :payload, as: :code, language: 'javascript', only_on: :edit, readonly: true
  field :payload, as: :code, language: 'javascript' do |model|
    JSON.pretty_generate(model.payload.as_json) if model.payload.present?
  end

  field :line_music_tracks, as: :has_many, searchable: true

  action FetchLineMusicAlbum
  action UpdateLineMusicAlbum
  action ProcessLineMusicJanToAlbumIds
end
