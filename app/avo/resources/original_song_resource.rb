# frozen_string_literal: true

class OriginalSongResource < Avo::BaseResource
  self.title = :title
  self.description = '原曲'
  self.includes = [:original]
  self.record_selector = false
  self.visible_on_sidebar = false
  self.search_query = lambda { |params:|
    scope.ransack(title_cont: params[:q], m: 'or').result(distinct: false)
  }

  field :id, as: :id, hide_on: [:index]
  field :original, as: :belongs_to
  field :title, as: :text, sortable: true
  field :composer, as: :text
  field :track_number, as: :number
  field :is_duplicate, as: :boolean
end
