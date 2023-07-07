# frozen_string_literal: true

class YtmusicTrackResource < Avo::BaseResource
  self.title = :name
  self.translation_key = 'avo.resource_translations.ytmusic_track'
  self.includes = %i[album track ytmusic_album]
  self.record_selector = false
  self.search_query = lambda {
    scope.ransack(name_cont: params[:q],
                  album_circles_name_cont: params[:q],
                  ytmusic_album_name_cont: params[:q],
                  m: 'or').result(distinct: false)
  }

  field :image_url, as: :external_image, name: 'image', hide_on: [:forms], as_avatar: :rounded
  field :id, as: :id, hide_on: [:index]
  field :album, as: :belongs_to, name: 'jan code', hide_on: [:index], readonly: true
  field :track, as: :belongs_to, name: 'isrc', hide_on: [:index], readonly: true
  field :circle_name, as: :text, hide_on: [:forms]
  field :ytmusic_album, as: :belongs_to, readonly: true
  field :name, as: :text, readonly: true, link_to_resource: true
  field :complex_name, as: :text, hide_on: :all, as_label: true do |model|
    "[#{model.circle_name}][#{model.ytmusic_album.name}] #{model.name}"
  end
  field :track_number, as: :number, readonly: true
  field :video_id, as: :text, required: true, hide_on: [:index]
  field :playlist_id, as: :text, required: true, hide_on: [:index]
  field :url, as: :text, format_using: -> { link_to(value, value, target: '_blank', rel: 'noopener') if value.present? }, hide_on: [:forms]
  field :payload, as: :code, language: 'javascript', only_on: :edit, readonly: true
  field :payload, as: :code, language: 'javascript' do |model|
    JSON.pretty_generate(model.payload.as_json) if model.payload.present?
  end

  action FetchYtmusicTrack
end
