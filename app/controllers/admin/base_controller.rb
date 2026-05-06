# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    include Pagy::Backend

    layout 'admin'
    before_action :set_spotify_rate_limit_status
    around_action :switch_admin_locale

    helper_method :admin_resources, :admin_resource_groups

    private

    def set_spotify_rate_limit_status
      @spotify_rate_limit_status = SpotifyRateLimit.current
    end

    def switch_admin_locale(&)
      I18n.with_locale(:ja, &)
    end

    def admin_resources
      Admin::Resource.all
    end

    def admin_resource_groups
      grouped_keys = {
        master: %w[originals original_songs master_artists circles],
        catalog: %w[albums tracks spotify_playlists],
        streaming: %w[
          spotify_albums spotify_tracks apple_music_albums apple_music_tracks
          line_music_albums line_music_tracks ytmusic_albums ytmusic_tracks
        ]
      }

      grouped_keys.filter_map do |group_key, resource_keys|
        resources = resource_keys.filter_map { |key| Admin::Resource.all.find { |resource| resource.key == key } }
        next if resources.empty?

        [group_key, resources]
      end
    end

    def authenticate_admin_if_configured
      username = ENV.fetch('ADMIN_USERNAME', nil)
      password = ENV.fetch('ADMIN_PASSWORD', nil)
      return if username.blank? || password.blank?

      authenticate_or_request_with_http_basic('Admin') do |provided_username, provided_password|
        ActiveSupport::SecurityUtils.secure_compare(provided_username, username) &
          ActiveSupport::SecurityUtils.secure_compare(provided_password, password)
      end
    end
  end
end
