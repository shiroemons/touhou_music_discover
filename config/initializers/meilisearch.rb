# frozen_string_literal: true

MeiliSearch::Rails.configuration = {
  meilisearch_host: ENV['MEILISEARCH_HOST'],
  meilisearch_api_key: ENV['MEILISEARCH_API_KEY']
}
