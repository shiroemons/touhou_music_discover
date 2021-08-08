# frozen_string_literal: true

MeiliSearch.configuration = {
  meilisearch_host: ENV['MEILISEARCH_HOST'],
  meilisearch_api_key: ENV['MEILISEARCH_API_KEY']
}
