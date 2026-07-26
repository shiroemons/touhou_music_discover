# frozen_string_literal: true

module SpotifyApi
  # Zeitwerk は errors.rb が SpotifyApi::Errors を定義していることを期待するため、
  # 名前空間として空のモジュールを置いておく。例外クラス自体は呼び出し側で
  # SpotifyApi::NotFoundError のように短く書けるよう SpotifyApi 直下に定義する。
  module Errors; end

  class Error < StandardError; end

  # クライアントID/シークレット未設定など、設定不備によるエラー。
  class ConfigurationError < Error; end

  # HTTP レスポンスを伴うエラーの基底。status / response / retry_after を保持する。
  class ApiError < Error
    attr_reader :status, :response, :retry_after

    def initialize(message, status: nil, response: nil, retry_after: nil)
      super(message)
      @status = status
      @response = response
      @retry_after = retry_after
    end
  end

  # 401
  class AuthenticationError < ApiError; end

  # 403
  class ForbiddenError < ApiError; end

  # 404
  class NotFoundError < ApiError; end

  # 429
  class RateLimitError < ApiError; end

  # 429 かつ reason == "QUOTA_EXCEEDED"。
  #
  # 2026年7月の変更で、Development Mode のクォータ超過は
  # {"error":{"status":429,"reason":"QUOTA_EXCEEDED"}} として返るようになった。
  # 通常のレート制限と違い短時間では回復しない（Retry-After が数時間規模になる）ため、
  # 呼び出し側でリトライせず打ち切るなど別扱いにできるよう独立した例外にする。
  # RateLimitError を継承しているので、区別が不要な箇所では従来どおり
  # RateLimitError で rescue できる。
  class QuotaExceededError < RateLimitError; end

  # 5xx
  class ServerError < ApiError; end
end
