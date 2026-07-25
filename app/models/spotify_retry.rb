# frozen_string_literal: true

# Spotify API 呼び出しの共通リトライ処理。
#
# - 429 (Too Many Requests) は Spotify が返す `Retry-After` ヘッダーに従って待機する
# - 一時的なサーバーエラー・タイムアウト系は指数バックオフ + ジッターで再試行する
#
# ブロックの呼び出しシグネチャは旧 retryable gem の retryable メソッドと互換にしてあるため、
# 既存の呼び出し箇所をほぼそのまま置き換えられる:
#
#   SpotifyRetry.with_retry(source: 'Admin::Actions::FetchSpotifyAudioFeatures') do |attempt, exception|
#     warn "try #{attempt} failed with exception: #{exception}" if attempt.positive?
#     # ... work ...
#   end
class SpotifyRetry
  DEFAULT_TRIES = 5
  DEFAULT_RETRY_AFTER = 30
  # Spotify がまれに非常に長い Retry-After (数時間単位) を返すことがあるため、
  # この秒数を超える場合は待たずに例外を再送出し、呼び出し元で処理を打ち切れるようにする
  DEFAULT_MAX_RETRY_AFTER = 900

  # 一時的なサーバーエラー・タイムアウト系の指数バックオフ設定
  BASE_SLEEP = 5
  MAX_SLEEP = 120
  JITTER = 0.3

  DEFAULT_SLEEPER = ->(seconds) { Kernel.sleep(seconds) }

  # 429 (レート制限)。Retry-After ヘッダーに従って待機する
  RATE_LIMIT_ERROR = RestClient::TooManyRequests

  # 一時的なサーバーエラー・タイムアウト系。指数バックオフ + ジッターで再試行する
  TRANSIENT_ERRORS = [
    RestClient::InternalServerError,
    RestClient::BadGateway,
    RestClient::ServiceUnavailable,
    RestClient::GatewayTimeout,
    RestClient::Exceptions::OpenTimeout,
    RestClient::Exceptions::ReadTimeout,
    Net::OpenTimeout,
    Net::ReadTimeout
  ].freeze

  class << self
    # @param source [String] SpotifyRateLimit に記録する呼び出し元の名前（管理画面バナーに表示される）
    # @param tries [Integer] 最大試行回数
    # @param max_retry_after [Integer] この秒数を超える Retry-After を受け取ったら待機せず再送出する
    # @param sleeper [#call] 実際の待機処理。テストでは差し替えて実際にはスリープさせない
    # @yieldparam attempt [Integer] 試行回数。初回は 0（旧 retryable gem と同じ挙動）
    # @yieldparam exception [Exception, nil] 直前の失敗の例外。初回は nil
    def with_retry(source:, tries: DEFAULT_TRIES, max_retry_after: DEFAULT_MAX_RETRY_AFTER, sleeper: DEFAULT_SLEEPER)
      attempt = 0
      exception = nil

      loop do
        return yield(attempt, exception)
      rescue RATE_LIMIT_ERROR => e
        attempt += 1
        exception = e
        sleeper.call(rate_limit_delay(e, source:, tries:, attempt:, max_retry_after:))
      rescue *TRANSIENT_ERRORS => e
        attempt += 1
        exception = e
        raise if attempt >= tries

        sleeper.call(transient_delay(attempt))
      end
    end

    private

    def rate_limit_delay(error, source:, tries:, attempt:, max_retry_after:)
      retry_after = SpotifyRateLimit.retry_after_seconds(error) || DEFAULT_RETRY_AFTER
      # 管理画面のバナーに反映するため、待機するかどうかに関わらず必ず記録する
      SpotifyRateLimit.record!(retry_after:, source:)

      raise error if retry_after > max_retry_after
      raise error if attempt >= tries

      retry_after
    end

    def transient_delay(attempt)
      base_delay = [BASE_SLEEP * (2**(attempt - 1)), MAX_SLEEP].min
      # 複数プロセス・スレッドが同時にリトライして再びサーバーに負荷が集中する
      # (thundering herd) のを避けるため、ジッターを加えてリトライ間隔を分散させる
      base_delay * (1 + (rand * JITTER))
    end
  end
end
