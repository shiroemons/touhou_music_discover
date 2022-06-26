# frozen_string_literal: true

class MasterArtistResource < Avo::BaseResource
  self.title = :name
  self.description = 'アーティストのマスターデータ'
  self.includes = []
  self.record_selector = false
  self.search_query = lambda { |params:|
    scope.ransack(name_cont: params[:q], key_eq: params[:q], m: 'or').result(distinct: false)
  }

  field :id, as: :id, hide_on: [:index]
  field :name, as: :text
  field :complex_name, as: :text, hide_on: :all, as_label: true do |model|
    "[#{model.streaming_type}][#{model.name}] #{model.key}"
  end
  field :key, as: :text
  field :streaming_type, as: :select, enum: ::MasterArtist.streaming_types, hide_on: %i[show index]
  field :streaming_type, as: :badge, options: { success: 'spotify', danger: 'apple_music' }
end
