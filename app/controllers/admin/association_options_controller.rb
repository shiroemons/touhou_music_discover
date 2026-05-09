# frozen_string_literal: true

module Admin
  class AssociationOptionsController < BaseController
    before_action :authenticate_admin_if_configured
    before_action :set_resource_config
    before_action :set_association

    def index
      render json: {
        options: association_records.map do |record|
          Admin::AssociationOption.as_json(record, primary_key: @association.association_primary_key)
        end
      }
    end

    private

    def set_resource_config
      @resource_config = Admin::Resource.find!(params[:resource])
    end

    def set_association
      @association = @resource_config.form_association_for(params[:attribute])
      raise ActiveRecord::RecordNotFound, "Unknown form association: #{params[:attribute]}" if @association.blank?
    end

    def association_records
      scope = association_scope
      query = params.fetch(:q, nil).to_s.strip
      scope = search_association_scope(scope, query) if query.present?

      records = scope
                .limit(Admin::Resource::FORM_ASSOCIATION_AUTOCOMPLETE_LIMIT)
                .to_a
                .uniq { |record| record.public_send(@association.association_primary_key).to_s }
      records.unshift(selected_record) if prepend_selected_record?(query, records)
      records
    end

    def association_scope
      if associated_resource.present?
        associated_resource.apply_to(@association.klass.all)
      else
        @association.klass.all
      end
    end

    def search_association_scope(scope, query)
      return associated_resource.search(scope, query) if associated_resource.present?

      fallback_search(scope, query)
    end

    def fallback_search(scope, query)
      pattern = "%#{scope.klass.sanitize_sql_like(query)}%"
      columns = %w[name title jan_code code spotify_id apple_music_id line_music_id browse_id video_id isrc]
      searchable_columns = columns & scope.klass.column_names
      clauses = searchable_columns.map { |column| "#{scope.klass.connection.quote_column_name(column)} ILIKE :query" }

      clauses << "#{scope.klass.connection.quote_column_name(scope.klass.primary_key)} = :id" if query.match?(/\A\d+\z/)

      return scope if clauses.empty?

      scope.where(clauses.join(' OR '), query: pattern, id: query)
    end

    def selected_record
      return if params[:selected].blank?
      return @selected_record if defined?(@selected_record)

      @selected_record = @association.klass.find_by(@association.association_primary_key => params[:selected])
    end

    def associated_resource
      @associated_resource ||= Admin::Resource.find_by_model_class(@association.klass)
    end

    def same_record?(left, right)
      left.public_send(@association.association_primary_key).to_s == right.public_send(@association.association_primary_key).to_s
    end

    def prepend_selected_record?(query, records)
      query.blank? && selected_record.present? && records.none? { |record| same_record?(record, selected_record) }
    end
  end
end
