# frozen_string_literal: true

module Admin
  module ResourcesHelper
    def admin_form_field(form, resource_config, record, attribute)
      column = resource_config.column_for(attribute)
      value = record.public_send(attribute) if record.respond_to?(attribute)
      field_id = "#{resource_config.key}_#{attribute}"

      content_tag(:div, class: 'admin-field') do
        safe_join(
          [
            form.label(attribute, resource_config.attribute_label(attribute), class: 'form-label', for: field_id),
            admin_input_for(form, column, attribute, value, field_id)
          ]
        )
      end
    end

    def admin_display_value(resource_config, record, attribute)
      value = resource_config.value_for(record, attribute)
      linked_value = admin_linked_record_value(attribute, value)
      return linked_value if linked_value

      case value
      when TrueClass
        tag.span('true', class: 'badge text-bg-success')
      when FalseClass
        tag.span('false', class: 'badge text-bg-secondary')
      when Hash, Array
        tag.pre(JSON.pretty_generate(value), class: 'mb-0 small text-wrap')
      when Time, DateTime
        value.in_time_zone('Asia/Tokyo').strftime('%Y-%m-%d %H:%M:%S')
      when Date
        value.iso8601
      else
        admin_scalar_value(attribute, value)
      end
    end

    def admin_resource_actions(resource_config, record: nil)
      resource_config.actions.select do |action|
        record.present? ? action.member? : action.collection?
      end
    end

    def admin_relation_sections(resource_config, record)
      resource_config.model_class.reflect_on_all_associations.filter_map do |reflection|
        Admin::RelationSection.new(resource_config:, record:, reflection:)
      end
    end

    def admin_record_label(record)
      %i[name title jan_code code spotify_id apple_music_id line_music_id browse_id video_id isrc id].each do |attribute|
        return record.public_send(attribute).to_s if record.respond_to?(attribute) && record.public_send(attribute).present?
      end

      record.to_param
    end

    private

    def admin_linked_record_value(attribute, value)
      return if value.blank?

      association = attribute.to_s.delete_suffix('_id')
      associated_resource = Admin::Resource.all.find do |resource|
        resource.model_class.name.underscore == association
      end
      return if associated_resource.blank?

      link_to(value, admin_resource_path(associated_resource.key, value))
    end

    def admin_input_for(form, column, attribute, value, field_id)
      return form.text_field(attribute, value:, class: 'form-control', id: field_id) if column.blank?

      case column.type
      when :boolean
        safe_join(
          [
            form.hidden_field(attribute, value: '0'),
            tag.div(class: 'form-check form-switch') do
              form.check_box(attribute, { checked: ActiveModel::Type::Boolean.new.cast(value), class: 'form-check-input', id: field_id }, '1', '0')
            end
          ]
        )
      when :text, :json, :jsonb
        text_value = value.is_a?(String) ? value : JSON.pretty_generate(value || {})
        form.text_area(attribute, value: text_value, rows: column.type.in?(%i[json jsonb]) ? 12 : 5, class: 'form-control font-monospace', id: field_id)
      when :integer, :float, :decimal
        form.number_field(attribute, value:, step: column.type == :integer ? 1 : 'any', class: 'form-control', id: field_id)
      when :date
        form.date_field(attribute, value:, class: 'form-control', id: field_id)
      when :datetime
        form.datetime_local_field(attribute, value: value&.strftime('%Y-%m-%dT%H:%M'), class: 'form-control', id: field_id)
      else
        form.text_field(attribute, value:, class: 'form-control', id: field_id)
      end
    end

    def admin_scalar_value(attribute, value)
      return tag.span(t('admin.shared.blank'), class: 'text-body-secondary') if value.blank?
      return link_to(value, value, target: '_blank', rel: 'noopener') if attribute.to_s.end_with?('url') && value.to_s.start_with?('http')

      value.to_s
    end
  end
end
