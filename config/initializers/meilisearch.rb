# frozen_string_literal: true

Meilisearch::Rails.configuration = {
  meilisearch_host: ENV.fetch('MEILISEARCH_HOST', nil),
  meilisearch_api_key: ENV.fetch('MEILISEARCH_API_KEY', nil)
}
