# frozen_string_literal: true

# For more information regaring these settings check out our docs https://docs.avohq.io
Avo.configure do |config|
  ## == Routing ==
  config.root_path = '/avo'

  # Where should the user be redirected when visting the `/avo` url
  # config.home_path = nil

  ## == Licensing ==
  config.license = ENV.fetch('AVO_LICENSE_KEY', 'community') # change this to 'pro' when you add the license key
  # config.license_key = ENV['AVO_LICENSE_KEY']

  ## == Set the context ==
  config.set_context do
    # Return a context object that gets evaluated in Avo::ApplicationController
  end

  ## == Authentication ==
  user = Struct.new(:name)

  config.current_user_method do
    user.new({ name: 'Anonymous user' })
  end
  # config.authenticate_with = {}

  ## == Authorization ==
  # config.authorization_methods = {
  #   index: 'index?',
  #   show: 'show?',
  #   edit: 'edit?',
  #   new: 'new?',
  #   update: 'update?',
  #   create: 'create?',
  #   destroy: 'destroy?',
  # }
  # config.raise_error_on_missing_policy = false

  ## == Localization ==
  config.locale = 'ja'

  ## == Customization ==
  # config.app_name = 'Avocadelicious'
  config.timezone = 'Asia/Tokyo'
  config.currency = 'JPY'
  # config.per_page = 24
  # config.per_page_steps = [12, 24, 48, 72]
  # config.via_per_page = 8
  # config.default_view_type = :table
  # config.hide_layout_when_printing = false
  # config.id_links_to_resource = false
  # config.full_width_container = false
  # config.full_width_index_view = false
  # config.cache_resources_on_index_view = true
  # config.search_debounce = 300
  # config.view_component_path = "app/components"
  # config.display_license_request_timeout_error = true
  # config.disabled_features = []

  ## == Breadcrumbs ==
  # config.display_breadcrumbs = true
  # config.set_initial_breadcrumbs do
  #   add_breadcrumb "Home", '/avo'
  # end
  config.resource_controls_placement = :left

  ## == Menus ==
  config.main_menu = lambda {
    section 'Dashboards', icon: 'dashboards' do
      all_dashboards
    end

    section 'Master data', icon: 'resources' do
      resource :original
      resource :original_song
      resource :master_artist
      resource :circle
    end

    section 'Resources', icon: 'resources' do
      group 'Common' do
        resource :album
        resource :track
      end

      group 'Spotify' do
        resource :spotify_album
        resource :spotify_track
        resource :spotify_track_audio_feature
      end

      group 'Apple Music' do
        resource :apple_music_album
        resource :apple_music_track
      end

      group 'YouTube Music' do
        resource :ytmusic_album
        resource :ytmusic_track
      end

      group 'LINE MUSIC' do
        resource :line_music_album
        resource :line_music_track
      end
    end

    #   section "Tools", icon: "tools" do
    #     all_tools
    #   end
    # }
    # config.profile_menu = -> {
    #   link "Profile", path: "/avo/profile", icon: "user-circle"
  }
end
