# frozen_string_literal: true

# errors.rb は1ファイルに複数の例外クラスを定義しており Zeitwerk の命名規約に
# 合わないため、ここで明示的に読み込む。
# （AppleMusic が config.rb に ParameterMissing / ApiError を同居させているのと同じ方針）
require_relative 'spotify_api/errors'

module SpotifyApi
  autoload :Album,         'spotify_api/album'
  autoload :AudioFeatures, 'spotify_api/audio_features'
  autoload :Client,        'spotify_api/client'
  autoload :Config,        'spotify_api/config'
  autoload :Page,          'spotify_api/page'
  autoload :Playlist,      'spotify_api/playlist'
  autoload :Response,      'spotify_api/response'
  autoload :Track,         'spotify_api/track'
  autoload :UserSession,   'spotify_api/user_session'

  class << self
    attr_writer :config

    def config
      @config ||= Config.new
    end

    def configure
      yield(config)
    end

    # NOTE: rspotify からの移行用フィーチャーフラグ。移行完了後（Issue #563）に
    #       このフラグと旧経路の分岐をまとめて削除する。
    def native_client_enabled?
      config.native_client_enabled
    end
  end
end
