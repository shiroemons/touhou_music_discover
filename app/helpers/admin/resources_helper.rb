# frozen_string_literal: true

module Admin
  module ResourcesHelper
    STREAMING_TRACK_STATUS_ACTIONS = {
      'SpotifyAlbum' => {
        association: :spotify_tracks,
        resource_key: 'spotify_albums',
        action_key: 'fetch_spotify_album'
      },
      'AppleMusicAlbum' => {
        association: :apple_music_tracks,
        resource_key: 'apple_music_tracks',
        action_key: 'fetch_apple_music_track'
      },
      'LineMusicAlbum' => {
        association: :line_music_tracks,
        resource_key: 'line_music_tracks',
        action_key: 'fetch_line_music_track'
      },
      'YtmusicAlbum' => {
        association: :ytmusic_tracks,
        resource_key: 'ytmusic_tracks',
        action_key: 'fetch_ytmusic_track'
      }
    }.freeze
    TRACK_STREAMING_SERVICES = {
      spotify: {
        label: 'Spotify',
        association: :spotify_tracks
      },
      apple_music: {
        label: 'Apple Music',
        association: :apple_music_tracks
      },
      line_music: {
        label: 'LINE MUSIC',
        association: :line_music_tracks
      },
      ytmusic: {
        label: 'YouTube Music',
        association: :ytmusic_tracks
      }
    }.freeze

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
      return admin_tracks_status_value(record) if attribute.to_s == 'tracks_status'
      return admin_streaming_tracks_status_value(record) if attribute.to_s == 'streaming_tracks_status'

      value = resource_config.value_for(record, attribute)
      reference_record = admin_reference_record(record, attribute, value)
      return admin_reference_value(reference_record) if reference_record

      case value
      when TrueClass
        tag.span('true', class: 'badge text-bg-success')
      when FalseClass
        tag.span('false', class: 'badge text-bg-secondary')
      when Hash, Array
        tag.pre(admin_pretty_json(value), class: 'admin-json-block')
      when Time, DateTime
        value.in_time_zone('Asia/Tokyo').strftime('%Y-%m-%d %H:%M:%S')
      when Date
        value.iso8601
      else
        admin_scalar_value(record, attribute, value)
      end
    end

    def admin_index_display_value(resource_config, record, attribute)
      value = resource_config.value_for(record, attribute)
      content = admin_display_value(resource_config, record, attribute)
      return content unless admin_linkable_index_attribute?(resource_config, attribute, value)

      link_to(content, admin_resource_path(resource_config.key, record), class: 'admin-index-record-link')
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

    def admin_relation_record_summary(record)
      tag.span(class: 'admin-relation-record-copy') do
        safe_join(
          [
            tag.span(admin_record_label(record), class: 'admin-relation-record-label'),
            tag.span(admin_relation_record_meta(record), class: 'admin-relation-record-meta')
          ].compact
        )
      end
    end

    def admin_record_label(record)
      %i[name title jan_code code spotify_id apple_music_id line_music_id browse_id video_id isrc id].each do |attribute|
        return record.public_send(attribute).to_s if record.respond_to?(attribute) && record.public_send(attribute).present?
      end

      record.to_param
    end

    def admin_active_filters?(resource_config, active_filters)
      params[:q].present? || resource_config.non_default_filters?(active_filters)
    end

    def admin_pagination(pagy)
      return if pagy.pages <= 1

      tag.nav(class: 'admin-pagination', aria: { label: t('admin.pagination.aria_label') }) do
        safe_join(
          [
            tag.div(
              t('admin.pagination.summary', from: pagy.from, to: pagy.to, count: pagy.count),
              class: 'admin-pagination-summary'
            ),
            tag.div(class: 'admin-pagination-controls') do
              safe_join(
                [
                  admin_pagination_link(1, t('admin.pagination.first'), disabled: pagy.page == 1, icon: 'bi-chevron-double-left'),
                  admin_pagination_link(pagy.prev || 1, t('admin.pagination.prev'), disabled: pagy.prev.blank?, icon: 'bi-chevron-left'),
                  tag.div(class: 'admin-pagination-pages') do
                    safe_join(admin_pagination_series(pagy).map { |item| admin_pagination_item(item, pagy.page) })
                  end,
                  admin_pagination_link(pagy.next || pagy.pages, t('admin.pagination.next'), disabled: pagy.next.blank?, icon: 'bi-chevron-right'),
                  admin_pagination_link(pagy.pages, t('admin.pagination.last'), disabled: pagy.page == pagy.pages, icon: 'bi-chevron-double-right')
                ]
              )
            end
          ]
        )
      end
    end

    private

    def admin_linkable_index_attribute?(resource_config, attribute, value)
      return false if value.blank?
      return false unless Admin::Resource.find_by_model_class(resource_config.model_class)

      attribute.to_s.in?(%w[name title short_title album_name spotify_album_name apple_music_album_name ytmusic_album_name line_music_album_name])
    end

    def admin_pretty_json(value)
      JSON.pretty_generate(value)
    rescue JSON::GeneratorError
      value.to_s
    end

    def admin_pagination_series(pagy)
      pages = ([1, pagy.pages] + ((pagy.page - 2)..(pagy.page + 2)).to_a)
              .select { |page| page.between?(1, pagy.pages) }
              .uniq
              .sort

      pages.each_cons(2).with_object([pages.first]) do |(previous_page, next_page), series|
        series << :gap if next_page - previous_page > 1
        series << next_page
      end
    end

    def admin_pagination_item(item, current_page)
      return tag.span('...', class: 'admin-pagination-gap', aria: { hidden: true }) if item == :gap

      admin_pagination_link(item, item.to_s, current: item == current_page)
    end

    def admin_pagination_link(page, label, disabled: false, current: false, icon: nil)
      classes = ['admin-pagination-link']
      classes << 'is-current' if current
      classes << 'is-disabled' if disabled

      content = if icon
                  safe_join(
                    [
                      tag.i(class: "bi #{icon}", aria: { hidden: true }),
                      tag.span(label, class: 'visually-hidden')
                    ]
                  )
                else
                  label
                end

      return tag.span(content, class: classes, aria: { current: current ? 'page' : nil }) if disabled || current

      link_to content, admin_pagination_url(page), class: classes, aria: { label: t('admin.pagination.go_to', page:) }
    end

    def admin_pagination_url(page)
      url_for(request.query_parameters.merge(page:))
    end

    def admin_tracks_status_value(record)
      action_config = STREAMING_TRACK_STATUS_ACTIONS[record.class.name]
      return tag.span(t('admin.shared.blank'), class: 'text-body-secondary') if action_config.blank?

      track_count = record.public_send(action_config.fetch(:association)).size
      total_tracks = record.respond_to?(:total_tracks) ? record.total_tracks.to_i : 0
      status_key = admin_tracks_status_key(track_count, total_tracks)
      count_label = total_tracks.positive? ? "#{track_count} / #{total_tracks}" : track_count.to_s

      tag.div(class: 'admin-track-status') do
        safe_join(
          [
            tag.span(count_label, class: 'admin-track-status-count'),
            tag.span(t("admin.track_status.#{status_key}"), class: "badge #{admin_tracks_status_badge_class(status_key)}"),
            admin_tracks_status_action_link(action_config, status_key)
          ].compact
        )
      end
    end

    def admin_tracks_status_key(track_count, total_tracks)
      return :missing if track_count.zero?
      return :incomplete if total_tracks.positive? && track_count < total_tracks
      return :complete if total_tracks.positive? && track_count >= total_tracks

      :present
    end

    def admin_tracks_status_badge_class(status_key)
      {
        missing: 'text-bg-danger',
        incomplete: 'text-bg-warning',
        complete: 'text-bg-success',
        present: 'text-bg-secondary'
      }.fetch(status_key)
    end

    def admin_tracks_status_action_link(action_config, status_key)
      return unless status_key.in?(%i[missing incomplete])

      link_to admin_resource_action_path(action_config.fetch(:resource_key), action_config.fetch(:action_key)),
              class: 'btn btn-sm admin-btn admin-track-status-action' do
        safe_join(
          [
            tag.i(class: 'bi bi-lightning-charge', aria: { hidden: true }),
            tag.span(t('admin.track_status.action'))
          ]
        )
      end
    end

    def admin_streaming_tracks_status_value(record)
      missing_services = TRACK_STREAMING_SERVICES.filter do |_key, service|
        record.respond_to?(service.fetch(:association)) && record.public_send(service.fetch(:association)).empty?
      end

      return tag.span(t('admin.streaming_status.complete'), class: 'badge text-bg-success') if missing_services.empty?

      tag.div(class: 'admin-streaming-status') do
        safe_join(
          missing_services.map do |key, service|
            link_to(
              t('admin.streaming_status.missing', service: service.fetch(:label)),
              admin_resources_path('tracks', filters: { missing_streaming_track: key }),
              class: 'badge text-bg-warning admin-streaming-status-badge'
            )
          end
        )
      end
    end

    def admin_relation_record_meta(record)
      values = []
      values << admin_track_position(record)
      values << t('admin.relations.meta.total_tracks', count: record.total_tracks) if record.respond_to?(:total_tracks) && record.total_tracks.present?
      values.compact.join(' / ').presence
    end

    def admin_track_position(record)
      return unless record.respond_to?(:track_number) && record.track_number.present?

      if record.respond_to?(:disc_number) && record.disc_number.present?
        t('admin.relations.meta.disc_track', disc: record.disc_number, track: record.track_number)
      else
        t('admin.relations.meta.track', track: record.track_number)
      end
    end

    def admin_reference_record(record, attribute, value)
      return if value.blank? || !attribute.to_s.end_with?('_id')

      association = attribute.to_s.delete_suffix('_id')
      reflection = record.class.reflect_on_association(association.to_sym)
      return unless reflection&.belongs_to? && record.respond_to?(association)

      associated_record = record.public_send(association)
      return associated_record if associated_record.present?

      reflection.klass.find_by(id: value)
    end

    def admin_reference_value(record)
      resource = Admin::Resource.find_by_model_class(record.class)
      content = admin_reference_content(record)

      return tag.span(content, class: 'admin-reference-card') if resource.blank?

      link_to(content, admin_resource_path(resource.key, record), class: 'admin-reference-card')
    end

    def admin_reference_content(record)
      label = admin_record_label(record)

      tag.span(class: 'admin-reference-copy') do
        safe_join(
          [
            tag.span(label, class: 'admin-reference-label'),
            tag.span(admin_reference_meta(record, label), class: 'admin-reference-meta')
          ].compact
        )
      end
    end

    def admin_record_thumbnail(record, label: admin_record_label(record))
      image_url = admin_record_image_url(record)
      return if image_url.blank?

      image_tag(image_url, alt: label, class: 'admin-record-thumb', loading: 'lazy')
    end

    def admin_record_image_url(record)
      return unless record.respond_to?(:image_url)

      record.image_url.presence
    rescue StandardError
      nil
    end

    def admin_reference_meta(record, label)
      values = %i[jan_code isrc spotify_id apple_music_id line_music_id browse_id video_id code]
               .filter_map { |attribute| admin_record_meta_value(record, attribute) }
               .reject { |value| value == label }
               .first(2)
      return if values.empty?

      values.join(' / ')
    end

    def admin_record_meta_value(record, attribute)
      return unless record.respond_to?(attribute)

      record.public_send(attribute).presence&.to_s
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

    def admin_scalar_value(record, attribute, value)
      return tag.span(t('admin.shared.blank'), class: 'text-body-secondary') if value.blank?
      return link_to(value, value, target: '_blank', rel: 'noopener') if attribute.to_s.end_with?('url') && value.to_s.start_with?('http')
      return admin_value_with_thumbnail(record, value) if admin_thumbnail_attribute?(attribute) && admin_record_image_url(record).present?

      value.to_s
    end

    def admin_thumbnail_attribute?(attribute)
      attribute.to_s.in?(%w[name title album_name spotify_album_name apple_music_album_name ytmusic_album_name line_music_album_name])
    end

    def admin_value_with_thumbnail(record, value)
      tag.span(class: 'admin-value-with-thumb') do
        safe_join(
          [
            admin_record_thumbnail(record, label: value.to_s),
            tag.span(value.to_s, class: 'admin-value-label')
          ]
        )
      end
    end
  end
end
