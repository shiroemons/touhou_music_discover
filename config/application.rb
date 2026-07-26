# frozen_string_literal: true

require_relative 'boot'

require 'rails'
# Pick the frameworks you want:
require 'active_model/railtie'
require 'active_job/railtie'
require 'active_record/railtie'
require 'active_storage/engine'
require 'action_controller/railtie'
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require 'action_view/railtie'
require 'action_cable/engine'
require 'rails/test_unit/railtie'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module TouhouMusicDiscover
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # omniauth: lib/omniauth/strategies/spotify.rb は OmniAuth::Strategies::Spotify を
    # 定義しており、Zeitwerk が期待する定数名（Omniauth::Strategies::Spotify、ディレクトリ名
    # ベースの小文字始まり）と一致しない。Zeitwerk の管理対象から外し、
    # config/initializers/omniauth.rb での明示 require に委ねる。
    config.autoload_lib(ignore: %w[assets tasks omniauth])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Redis cache store設定 (Rails 8対応)
    #
    # 開発環境は :memory_store（config/environments/development.rb）、
    # テスト環境は :null_store（config/environments/test.rb）で上書きされるため、
    # 以下の redis_cache_store 設定は実質的に本番環境（および明示的に上書きしていない環境）でのみ有効。
    #
    # - REDIS_URL 未設定時に URL が "/0" に縮退してしまう不具合を修正するため、
    #   デフォルト値 'redis://localhost:6379' を明示。
    # - REDIS_URL 末尾にスラッシュが付く場合（例: docker-compose.yml の
    #   REDIS_URL=redis://redis:6379/）に "//0" と二重スラッシュになる不具合を
    #   .chomp('/') で修正。
    # - pool を追加し、PumaのスレッドプールサイズにあわせてRedis接続を並列化
    #   （未設定だとRedisアクセスがPumaのスレッド数と無関係に直列化されてしまう）。
    # - connect/read/write の timeout を設定し、Redisがハングした場合に
    #   リクエストが無期限にブロックされないようにする。
    # - reconnect_attempts で一時的な接続断からの再接続をリトライする。
    # - error_handler を追加し、Redis障害時に例外がそのままアプリに伝播するのを防ぎ、
    #   ログに記録した上でフォールバック動作（returning値）に委ねる
    #   （従来は Admin::BaseController が独自に rescue していただけだった）。
    config.cache_store = :redis_cache_store, {
      url: "#{ENV.fetch('REDIS_URL', 'redis://localhost:6379').chomp('/')}/0",
      namespace: 'cache',
      expires_in: 90.minutes,
      pool: { size: ENV.fetch('RAILS_MAX_THREADS', 3).to_i, timeout: 5 },
      connect_timeout: 1,
      read_timeout: 1,
      write_timeout: 1,
      reconnect_attempts: [0.05, 0.1, 0.2],
      error_handler: lambda { |method:, returning:, exception:|
        Rails.logger.error("[redis_cache_store] #{method} failed (returning #{returning.inspect}): #{exception.class}: #{exception.message}")
      }
    }

    config.i18n.default_locale = :ja
    config.i18n.available_locales = %i[ja en]
  end
end
