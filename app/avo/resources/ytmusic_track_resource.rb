# frozen_string_literal: true

class YtmusicTrackResource < Avo::BaseResource
  self.title = :name
  self.description = 'YouTube Music トラック'
  self.includes = %i[album track ytmusic_album]
  self.record_selector = false
  self.search_query = lambda { |params:|
    scope.ransack(name_cont: params[:q],
                  album_circles_name_cont: params[:q],
                  ytmusic_album_name_cont: params[:q],
                  m: 'or').result(distinct: false)
  }

  field :image_url, as: :external_image, name: 'image', hide_on: [:forms], as_avatar: :rounded
  field :id, as: :id, hide_on: [:index]
  field :album, as: :belongs_to, name: 'jan code', searchable: true
  field :track, as: :belongs_to, name: 'isrc', searchable: true
  field :circle_name, as: :text, hide_on: [:forms]
  field :ytmusic_album, as: :belongs_to, searchable: true
  field :name, as: :text, readonly: true
  field :complex_name, as: :text, hide_on: :all, as_label: true do |model|
    "[#{model.circle_name}][#{model.ytmusic_album.name}] #{model.name}"
  end
  field :track_number, as: :number, readonly: true
  field :video_id, as: :text, required: true
  field :playlist_id, as: :text, required: true
  field :url, as: :text, format_using: ->(url) { link_to(url, url, target: '_blank', rel: 'noopener') if url.present? }, hide_on: [:forms]
end
