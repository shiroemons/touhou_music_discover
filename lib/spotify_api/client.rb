# frozen_string_literal: true

require 'faraday'
require 'faraday/net_http'

module SpotifyApi
  class Client
    # connection はテストで Faraday テストアダプタを差し込むための注入口。
    def initialize(config = SpotifyApi.config, connection: nil)
      @config = config
      @connection = connection
    end

    # access_token を渡すと、既定のアプリトークン（Client Credentials）ではなく
    # そのトークンを使う。ユーザー単位の操作（プレイリスト編集など）で使用する。
    #
    # access_token がキーワード引数のため、params / body は必ず Hash リテラルとして
    # 波かっこ付きで渡すこと（get('search', { q: 'touhou' })）。
    # 波かっこを省くとキーワード引数として解釈される。
    def get(path, params = {}, access_token: nil)
      response = connection.get(path, params) { |req| apply_access_token(req, access_token) }
      handle_response(response)
    end

    def post(path, body = {}, access_token: nil)
      response = connection.post(path, body) { |req| apply_access_token(req, access_token) }
      handle_response(response)
    end

    def put(path, body = {}, access_token: nil)
      response = connection.put(path, body) { |req| apply_access_token(req, access_token) }
      handle_response(response)
    end

    # Spotify のプレイリスト項目削除は body を伴うため、DELETE でも body を受け取れるようにする。
    def delete(path, body = nil, access_token: nil)
      response = connection.delete(path) do |req|
        req.body = body unless body.nil?
        apply_access_token(req, access_token)
      end
      handle_response(response)
    end

    private

    attr_reader :config

    def connection
      @connection ||= ExternalApi::Connection.build(:spotify, url: Config::API_URL, adapter: config.adapter) do |conn|
        conn.request :json
        conn.response :json, content_type: /\bjson$/
        # Proc を渡すとリクエストごとに評価されるため、トークンの期限切れ後も
        # 更新されたトークンが使われる（コネクション生成時の値に固定されない）。
        conn.request :authorization, 'Bearer', -> { config.access_token }
      end
    end

    # Faraday の authorization ミドルウェアは既に Authorization ヘッダがある場合は何もしないため、
    # ここで設定した値がアプリトークンより優先される。
    def apply_access_token(request, access_token)
      request.headers['Authorization'] = "Bearer #{access_token}" if access_token.present?
    end

    # 取得済みのレスポンスをそのまま返すだけで、追加の HTTP リクエストは一切行わない。
    #
    # 削除済みの旧 rspotify 経路（RSpotify::Base#method_missing）は、未取得の属性に
    # アクセスされると裏で API を叩き直していた。この暗黙のリクエストが Development Mode の
    # クォータ枯渇の主因だったため、SpotifyApi では同様の仕組みを絶対に実装しない。
    def handle_response(response)
      status = response.status
      return response.body if status.between?(200, 299)

      body = response.body.is_a?(Hash) ? response.body : {}
      message = body.dig('error', 'message') || "Spotify API request failed with status #{status}"

      raise error_class(status, body).new(message, status:, response:, retry_after: retry_after(response))
    end

    def error_class(status, body)
      case status
      when 401 then AuthenticationError
      when 403 then ForbiddenError
      when 404 then NotFoundError
      when 429 then quota_exceeded?(body) ? QuotaExceededError : RateLimitError
      when 500..599 then ServerError
      else ApiError
      end
    end

    # Development Mode のクォータ超過は 429 かつ reason が QUOTA_EXCEEDED で返る。
    def quota_exceeded?(body)
      body.dig('error', 'reason') == 'QUOTA_EXCEEDED'
    end

    def retry_after(response)
      response.headers['retry-after']&.to_i
    end
  end
end
