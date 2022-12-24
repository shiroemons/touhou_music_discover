# frozen_string_literal: true

class LineMusicTrackResource < Avo::BaseResource
  self.title = :name
  self.translation_key = 'avo.resource_translations.line_music_track'
  self.includes = %i[album track line_music_album]
  self.record_selector = false
  self.search_query = lambda {
    scope.ransack(name_cont: params[:q],
                  album_circles_name_cont: params[:q],
                  line_music_album_name_cont: params[:q],
                  m: 'or').result(distinct: false)
  }

  field :image_url, as: :external_image, name: 'image', hide_on: [:forms], as_avatar: :rounded
  field :id, as: :id, hide_on: [:index]
  field :album, as: :belongs_to, name: 'jan code', hide_on: [:index], readonly: true
  field :track, as: :belongs_to, name: 'isrc', hide_on: [:index], readonly: true
  field :circle_name, as: :text, hide_on: [:forms]
  field :line_music_album, as: :belongs_to, readonly: true
  field :name, as: :text, sortable: true, readonly: true, link_to_resource: true
  field :complex_name, as: :text, hide_on: :all, as_label: true do |model|
    "[#{model.circle_name}][#{model.line_music_album.name}] #{model.name}"
  end
  field :disc_number, as: :number, readonly: true
  field :track_number, as: :number, readonly: true
  field :line_music_id, as: :text, required: true, hide_on: [:index]
  field :url, as: :text, format_using: ->(url) { link_to(url, url, target: '_blank', rel: 'noopener') if url.present? }, hide_on: [:forms]
  field :payload, as: :code, language: 'javascript', only_on: :edit, readonly: true
  field :payload, as: :code, language: 'javascript' do |model|
    if model.payload.present?
      JSON.pretty_generate(model.payload.as_json)
    end
  end

  action FetchLineMusicTrack
  action UpdateLineMusicTrack
end
