# frozen_string_literal: true

module Admin
  class RelationSection
    PREVIEW_LIMIT = 10

    attr_reader :resource_config, :record, :reflection

    delegate :name, :macro, to: :reflection

    def initialize(resource_config:, record:, reflection:)
      @resource_config = resource_config
      @record = record
      @reflection = reflection
    end

    def label
      I18n.t("admin.relations.labels.#{name}", default: name.to_s.humanize)
    end

    def associated_resource
      Admin::Resource.find_by_model_class(reflection.klass)
    rescue NameError
      nil
    end

    def collection?
      macro.in?(%i[has_many has_and_belongs_to_many])
    end

    def records
      return Array(record.public_send(name)).compact unless collection?

      record.public_send(name).limit(PREVIEW_LIMIT)
    end

    def count
      value = record.public_send(name)
      collection? ? value.count : Array(value).compact.size
    end

    def empty?
      count.zero?
    end

    def more?
      collection? && count > PREVIEW_LIMIT
    end
  end
end
