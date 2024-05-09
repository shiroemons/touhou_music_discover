# frozen_string_literal: true

class CircleResource < Avo::BaseResource
  self.title = :name
  self.translation_key = 'avo.resource_translations.circle'
  self.includes = []
  self.record_selector = false
  self.search_query = lambda {
    scope.ransack(name_cont: params[:q], m: 'or').result(distinct: false)
  }

  field :id, as: :id, hide_on: [:index]
  field :name, as: :text
  field :albums_count, as: :number, only_on: [:index], index_text_align: :right

  field :albums, as: :has_many, hide_on: [:new, :edit]
end
