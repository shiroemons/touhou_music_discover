# frozen_string_literal: true

require 'base64'

module SpotifyApi
  # ユーザー単位の Authorization Code トークン（プレイリスト編集など、ユーザー本人の
  # 権限が必要な操作）を扱う。Client Credentials フローで取得するアプリトークンを
  # 扱う SpotifyApi::Config とは別物。
  #
  # app/controllers/sessions_controller.rb が OmniAuth の auth_hash を
  # redis.set(user.id, auth_hash.to_json) で保存しているため、find はその値を
  # 読み込んで UserSession を組み立てる。auth_hash は JSON 経由なのでキーは
  # 文字列である点に注意（credentials['token'] のようにアクセスする）。
  class UserSession
    REFRESH_MARGIN = 60.seconds # 期限切れ前に再取得を始めるマージン（SpotifyApi::Config と同じ考え方）

    class << self
      # Redis から auth_hash を読み込んで UserSession を組み立てる。該当キーが無ければ nil を返す。
      #
      # rspotify の RSpotify::User は該当ユーザーの認証情報が見つからないと
      # 「最初に登録されたユーザーのトークン」にフォールバックする（rspotify/user.rb:66）。
      # マルチユーザー環境では別人のアカウントにプレイリストを書き込む事故につながるため、
      # SpotifyApi ではこの挙動を絶対に引き継がない。見つからなければ黙って nil を返すだけにする。
      def find(user_id, config: SpotifyApi.config)
        json = RedisPool.with { |redis| redis.get(user_id) }
        return nil if json.blank?

        new(JSON.parse(json), user_id:, config:)
      end
    end

    attr_reader :auth_hash

    # user_id を渡すと、リフレッシュ成功時に Redis への書き戻しを行う（.find 経由の想定）。
    # config はテストから Client と同じ流儀（DI）で差し替えるための注入口。
    def initialize(auth_hash, user_id: nil, config: SpotifyApi.config)
      @auth_hash = auth_hash
      @user_id = user_id
      @config = config
      # access_token の期限チェック〜リフレッシュ〜Redis書き戻しを排他制御する。
      # 複数スレッドから同時に呼ばれても二重にリフレッシュしないようにするため。
      @mutex = Mutex.new
    end

    def spotify_user_id
      auth_hash['uid']
    end

    def refresh_token
      credentials['refresh_token']
    end

    def expires_at
      Time.zone.at(credentials['expires_at'].to_i)
    end

    def expired?
      expires_at - REFRESH_MARGIN <= Time.current
    end

    # 有効なアクセストークンを返す。期限切れ間近なら事前にリフレッシュしてから返す。
    #
    # rspotify は 401 が返ってきてからエラーメッセージの文字列マッチでリフレッシュしており
    # （RSpotify::Base#method_missing 経由）、そのぶん毎回1往復を無駄にしている。
    # ここでは期限を先読みしてリフレッシュすることで、その無駄な往復を無くす。
    def access_token
      @mutex.synchronize do
        perform_refresh! if expired?
        credentials['token']
      end
    end

    # 期限に関わらず強制的にリフレッシュする。
    def refresh!
      @mutex.synchronize { perform_refresh! }
      credentials['token']
    end

    private

    attr_reader :user_id, :config

    def credentials
      auth_hash['credentials'] ||= {}
    end

    def perform_refresh!
      raise AuthenticationError, 'refresh_token is missing; cannot refresh Spotify access token' if refresh_token.blank?

      response = request_token_refresh
      raise AuthenticationError.new("Failed to refresh Spotify access token with status #{response.status}", status: response.status, response:) unless response.status == 200

      apply_refreshed_credentials(response.body || {})
      persist!
    end

    def apply_refreshed_credentials(body)
      credentials['token'] = body['access_token']
      credentials['expires_at'] = (Time.current + (body['expires_in'] || Config::DEFAULT_TOKEN_TTL).to_i).to_i
      credentials['expires'] = true
      # レスポンスに refresh_token が含まれないことがある（Spotify の仕様）。
      # ここで上書きして nil にすると以後リフレッシュ不能になるため、含まれている
      # 場合だけ更新し、含まれていなければ既存の refresh_token を維持する。
      credentials['refresh_token'] = body['refresh_token'] if body['refresh_token'].present?
    end

    def request_token_refresh
      config.token_connection.post('/api/token') do |req|
        req.headers['Authorization'] = "Basic #{Base64.strict_encode64("#{config.client_id}:#{config.client_secret}")}"
        req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
        req.body = URI.encode_www_form(grant_type: 'refresh_token', refresh_token:)
      end
    end

    # user_id が分かっている場合（.find 経由で生成されたとき）だけ Redis に書き戻す。
    # 書き戻しに失敗しても例外は伝播させない。ここで落とすとプレイリスト更新処理
    # 全体が失敗してしまうため、取得済みのトークンはそのまま使わせ、warn ログのみ残す。
    def persist!
      return if user_id.blank?

      RedisPool.with { |redis| redis.set(user_id, auth_hash.to_json) }
    rescue StandardError => e
      Rails.logger.warn("SpotifyApi::UserSession#persist!: failed to write back to Redis (#{e.class}: #{e.message})")
    end
  end
end
