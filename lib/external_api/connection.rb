# frozen_string_literal: true

require 'faraday'
require 'faraday/retry'

module ExternalApi
  # 外部API向け Faraday コネクションの共通ビルダー。
  #
  # タイムアウト値とリトライ条件をこのファイル1か所に集約し、
  # 各クライアントでは認証やエンコーディングなど、そのAPI固有の設定だけを行う。
  module Connection
    # 全プロファイル共通のリトライ条件。
    #
    # retry_statuses について:
    #   faraday-retry (Faraday::Retry::Middleware#call) は、レスポンスの
    #   ステータスが retry_statuses に含まれる場合にのみ Faraday::RetriableResponse を
    #   送出してリトライを発生させる。待機時間を決める calculate_sleep_amount /
    #   calculate_retry_after も同じ経路でしか呼ばれないため、Retry-After ヘッダが
    #   尊重されるかどうかもこの指定に依存する。
    #   つまり retry_statuses を省略すると、429 のレート制限はリトライされず
    #   Retry-After も無視される。
    #   この共通設定はプロファイル側の retry に同じキーを書くことで上書きできる
    #   （build 内のマージ順が **SHARED_RETRY_OPTIONS, **profile[:retry] のため）。
    #
    # exceptions について:
    #   接続断・タイムアウト系は再送で回復する見込みがあるためリトライ対象に含める。
    SHARED_RETRY_OPTIONS = {
      retry_statuses: [429, 500, 502, 503, 504],
      exceptions: [
        Faraday::ConnectionFailed,
        Faraday::SSLError,
        Faraday::TimeoutError,
        Net::OpenTimeout,
        Net::ReadTimeout,
        Errno::ECONNRESET,
        Errno::EHOSTUNREACH
      ].freeze
    }.freeze

    # サービスごとのタイムアウト・リトライ設定。
    #
    # methods に :post を明示している理由:
    #   faraday-retry の既定値 IDEMPOTENT_METHODS は %i[delete get head options put] で、
    #   :post を含まない。YouTube Music の検索・browse は POST で行うため、
    #   従来 yt_music クライアントに書かれていた retry 設定は実質一度も発火していなかった。
    #   対象APIの POST はいずれも参照系（検索・取得）で再送しても副作用がないため、
    #   明示的に :post をリトライ対象に含める。
    PROFILES = {
      yt_music: {
        open_timeout: 5,
        timeout: 15,
        # YouTube Musicは短時間に検索が続くと、一時的なアクセス制限を403で返すことがある。
        # 認証切れ等の恒久的な403は最大3回で打ち切り、呼び出し側へ明示的なエラーとして返す。
        retry: {
          max: 3, interval: 0.5, backoff_factor: 2, max_interval: 10,
          interval_randomness: 0.3, methods: %i[get post],
          retry_statuses: [403, 429, 500, 502, 503, 504]
        }
      },
      line_music: {
        open_timeout: 5,
        timeout: 10,
        retry: { max: 3, interval: 1.0, backoff_factor: 2, max_interval: 15, interval_randomness: 0.5, methods: %i[get post] }
      },
      apple_music: {
        open_timeout: 5,
        timeout: 15,
        retry: { max: 3, interval: 1.0, backoff_factor: 2, max_interval: 20, interval_randomness: 0.5, methods: %i[get post] }
      },
      github: {
        open_timeout: 5,
        timeout: 30,
        retry: { max: 2, interval: 1.0, backoff_factor: 2, max_interval: 10, interval_randomness: 0.5, methods: %i[get] }
      },
      # spotify だけ retry_statuses から 429 を意図的に除外している。
      #   Spotify は Development Mode のクォータ超過時に Retry-After: 64063（約17.8時間）のような
      #   極端な値を返すことがあり、faraday-retry はその値ぶんスレッドをブロックして待機してしまう。
      #   429 のハンドリングは既存の SpotifyRetry / SpotifyRateLimit（app/models 配下）に委ね、
      #   Faraday 層では 5xx の一時的な障害だけをリトライ対象にする。
      spotify: {
        open_timeout: 5,
        timeout: 15,
        retry: {
          max: 3, interval: 1.0, backoff_factor: 2, max_interval: 20,
          interval_randomness: 0.3, methods: %i[get],
          retry_statuses: [500, 502, 503, 504]
        }
      },
      # accounts.spotify.com（トークン取得）専用。
      #   POST しかないエンドポイントであり、client_credentials / refresh_token の取得は
      #   何度実行しても副作用がないため :post をリトライ対象に含める。
      #   API 本体（spotify プロファイル）の POST はプレイリストへの項目追加など
      #   非冪等な操作を含むため、そちらでは :post をリトライしない。
      spotify_accounts: {
        open_timeout: 5,
        timeout: 10,
        retry: {
          max: 3, interval: 1.0, backoff_factor: 2, max_interval: 20,
          interval_randomness: 0.3, methods: %i[post],
          retry_statuses: [500, 502, 503, 504]
        }
      }
    }.freeze

    class UnknownService < ArgumentError; end

    class << self
      # 指定サービスのプロファイルを適用した Faraday::Connection を返す。
      #
      # ブロックを渡すと、リトライ設定の後・アダプタ設定の前に呼び出されるため、
      # リクエスト/レスポンスミドルウェア（:json など）を追加できる。
      def build(service, url: nil, adapter: nil, &block)
        profile = PROFILES.fetch(service) do
          raise UnknownService, "未定義の外部APIサービスです: #{service.inspect} (利用可能: #{PROFILES.keys.join(', ')})"
        end

        Faraday.new(url ? { url: } : {}) do |conn|
          conn.options.open_timeout = profile[:open_timeout]
          conn.options.timeout = profile[:timeout]
          # プロファイル側の指定を後に展開し、共通設定を上書きできるようにする。
          conn.request :retry, **SHARED_RETRY_OPTIONS, **profile[:retry]
          conn.response :logger, Rails.logger, headers: false, bodies: false if Rails.env.development?

          block&.call(conn)

          # Faraday はアダプタがハンドラスタックの末尾にあることを要求するため、
          # 呼び出し側ブロックが何を追加しても最後に設定されるようここで呼ぶ。
          conn.adapter(adapter || Faraday.default_adapter)
        end
      end
    end
  end
end
