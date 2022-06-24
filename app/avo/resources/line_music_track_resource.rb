# frozen_string_literal: true

class LineMusicTrackResource < Avo::BaseResource
  self.title = :name
  self.description = 'LINE MUSIC トラック'
  self.includes = %i[album track line_music_album]
  self.record_selector = false
  self.search_query = lambda { |params:|
    scope.ransack(name_cont: params[:q],
                  album_circles_name_cont: params[:q],
                  line_music_album_name_cont: params[:q],
                  m: 'or').result(distinct: false)
  }

  field :image_url, as: :external_image, name: 'image', hide_on: [:forms], as_avatar: :rounded
  field :id, as: :id, hide_on: [:index]
  field :album, as: :belongs_to, name: 'jan code'
  field :track, as: :belongs_to, name: 'isrc'
  field :circle_name, as: :text, hide_on: [:forms]
  field :line_music_album, as: :belongs_to
  field :name, as: :text, sortable: true
  field :complex_name, as: :text, hide_on: :all, as_label: true do |model|
    "[#{model.circle_name}][#{model.line_music_album.name}] #{model.name}"
  end
  field :disc_number, as: :number
  field :track_number, as: :number
  field :line_music_id, as: :text
  field :url, as: :text, format_using: ->(url) { link_to(url, url, target: '_blank', rel: 'noopener') }
end
