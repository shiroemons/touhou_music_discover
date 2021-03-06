# frozen_string_literal: true

class AppleMusicTrackResource < Avo::BaseResource
  self.title = :name
  self.description = 'Apple Music トラック'
  self.includes = %i[album track apple_music_album]
  self.record_selector = false
  self.search_query = lambda { |params:|
    scope.ransack(name_cont: params[:q],
                  album_circles_name_cont: params[:q],
                  apple_music_album_name_cont: params[:q],
                  m: 'or').result(distinct: false)
  }

  field :image_url, as: :external_image, name: 'image', hide_on: [:forms], as_avatar: :rounded
  field :id, as: :id, hide_on: [:index]
  field :album, as: :belongs_to, name: 'jan code', searchable: true
  field :track, as: :belongs_to, name: 'isrc', searchable: true
  field :circle_name, as: :text, hide_on: [:forms]
  field :apple_music_album, as: :belongs_to, searchable: true
  field :name, as: :text, sortable: true, readonly: true
  field :complex_name, as: :text, hide_on: :all, as_label: true do |model|
    "[#{model.circle_name}][#{model.apple_music_album.name}] #{model.name}"
  end
  field :label, as: :text, hide_on: [:index], readonly: true
  field :artist_name, as: :text, hide_on: [:index], readonly: true
  field :composer_name, as: :text, hide_on: [:index], readonly: true
  field :release_date, as: :date, format: '%Y-%m-%d', readonly: true
  field :disc_number, as: :number, readonly: true
  field :track_number, as: :number, readonly: true
  field :duration_ms, as: :number, readonly: true
  field :apple_music_id, as: :text, required: true
  field :url, as: :text, format_using: ->(url) { link_to(url, url, target: '_blank', rel: 'noopener') if url.present? }, hide_on: [:forms]
end
