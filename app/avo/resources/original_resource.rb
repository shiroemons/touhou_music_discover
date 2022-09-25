# frozen_string_literal: true

class OriginalResource < Avo::BaseResource
  self.title = :title
  self.description = '原作'
  self.includes = [:original_songs]
  self.record_selector = false
  self.visible_on_sidebar = false
  self.search_query = lambda {
    scope.ransack(title_cont: params[:q], m: 'or').result(distinct: false)
  }

  field :id, as: :id, hide_on: [:index]
  field :title, as: :text, sortable: true
  field :short_title, as: :text, sortable: true
  field :original_type, as: :badge
  field :series_order, as: :number

  field :original_songs, as: :has_many
end
