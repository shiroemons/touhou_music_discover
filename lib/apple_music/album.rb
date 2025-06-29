# frozen_string_literal: true

module AppleMusic
  class Album
    class << self
      def find(id, storefront: AppleMusic.config.storefront)
        path = build_path(storefront, id)
        response = connection.get(path)
        Response.new(response).first
      end

      def list(ids: [], upc: '', storefront: AppleMusic.config.storefront)
        return get_collection_by_ids(ids, storefront: storefront) if ids.present?
        return get_collection_by_upc(upc, storefront: storefront) if upc.present?

        raise ParameterMissing, 'Either ids or upc must be provided'
      end

      def get_collection_by_ids(ids, storefront: AppleMusic.config.storefront)
        ids_string = ids.is_a?(Array) ? ids.join(',') : ids
        path = build_path(storefront)
        params = { ids: ids_string }

        response = connection.get(path, params)
        Response.new(response).items
      end

      def get_collection_by_upc(upc, storefront: AppleMusic.config.storefront)
        path = build_path(storefront)
        params = { 'filter[upc]' => upc }

        response = connection.get(path, params)
        Response.new(response).items
      end

      def get_relationship(id, relationship_type, limit: nil, offset: nil, storefront: AppleMusic.config.storefront)
        path = build_path(storefront, id, relationship_type)
        params = {}
        params[:limit] = limit if limit
        params[:offset] = offset if offset

        response = connection.get(path, params)
        Response.new(response).items
      end

      def search(term, limit: nil, offset: nil, storefront: AppleMusic.config.storefront)
        path = "catalog/#{storefront}/search"
        params = {
          term: term,
          types: 'albums'
        }
        params[:limit] = limit if limit
        params[:offset] = offset if offset

        response = connection.get(path, params)
        Response.new(response).results
      end

      private

      def connection
        @connection ||= Client.new(AppleMusic.config)
      end

      def build_path(storefront, *segments)
        path_parts = ['catalog', storefront, 'albums', *segments].compact
        path_parts.join('/')
      end
    end
  end
end
