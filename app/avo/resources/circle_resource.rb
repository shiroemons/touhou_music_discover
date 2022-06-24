# frozen_string_literal: true

class CircleResource < Avo::BaseResource
  self.title = :name
  self.description = 'サークル'
  self.includes = []
  self.record_selector = false
  self.search_query = lambda { |params:|
    scope.ransack(name_cont: params[:q], m: 'or').result(distinct: false)
  }

  field :id, as: :id, hide_on: [:index]
  field :name, as: :text
end
