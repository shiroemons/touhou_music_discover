# frozen_string_literal: true

module Admin
  module ResourcesHelper
    include Resources::DisplayHelper
    include Resources::ExternalLinksHelper
    include Resources::FormHelper
    include Resources::NavigationHelper
    include Resources::PaginationHelper
    include Resources::RelationHelper
    include Resources::StatusHelper
  end
end
