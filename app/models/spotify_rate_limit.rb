# frozen_string_literal: true

class SpotifyRateLimit
  CACHE_KEY = 'spotify_rate_limit:current'
  CACHE_GRACE_PERIOD = 5.minutes
  DISPLAY_TIME_ZONE = 'Asia/Tokyo'

  Status = Data.define(:retry_after, :observed_at, :expires_at, :source) do
    def remaining_seconds(now: Time.current)
      [(expires_at - now).ceil, 0].max
    end

    def retry_after_duration
      SpotifyRateLimit.format_duration(retry_after)
    end

    def observed_at_jst
      observed_at.in_time_zone(SpotifyRateLimit::DISPLAY_TIME_ZONE)
    end

    def expires_at_jst
      expires_at.in_time_zone(SpotifyRateLimit::DISPLAY_TIME_ZONE)
    end
  end

  class << self
    attr_writer :cache_store

    def record!(retry_after:, source: nil, observed_at: Time.current)
      retry_after = retry_after.to_i
      return if retry_after <= 0

      status = Status.new(
        retry_after:,
        observed_at:,
        expires_at: observed_at + retry_after.seconds,
        source:
      )

      cache_store.write(CACHE_KEY, serialize(status), expires_in: retry_after.seconds + CACHE_GRACE_PERIOD)
      status
    rescue StandardError => e
      Rails.logger.warn("Could not record Spotify rate limit status: #{e.class}: #{e.message}")
      status
    end

    def record_from_error!(error, source: nil, observed_at: Time.current)
      record!(retry_after: retry_after_seconds(error), source:, observed_at:)
    end

    def current(now: Time.current)
      status = deserialize(cache_store.read(CACHE_KEY))
      return if status.blank?
      return status if status.remaining_seconds(now:).positive?

      cache_store.delete(CACHE_KEY)
      nil
    rescue StandardError => e
      Rails.logger.warn("Could not read Spotify rate limit status: #{e.class}: #{e.message}")
      nil
    end

    def retry_after_seconds(error)
      headers = error.http_headers if error.respond_to?(:http_headers)
      retry_after = headers&.[](:retry_after) || headers&.[]('retry-after')
      retry_after ||= error.response&.headers&.dig(:retry_after)
      retry_after ||= error.response&.headers&.dig('retry-after')
      retry_after&.to_i
    end

    def format_duration(total_seconds)
      total_seconds = total_seconds.to_i
      return I18n.t('admin.spotify_rate_limit.duration.seconds', seconds: 0) if total_seconds <= 0

      hours = total_seconds / 3600
      minutes = (total_seconds % 3600) / 60
      seconds = total_seconds % 60

      parts = []
      parts << I18n.t('admin.spotify_rate_limit.duration.hours', hours:) if hours.positive?
      parts << I18n.t('admin.spotify_rate_limit.duration.minutes', minutes:) if minutes.positive?
      parts << I18n.t('admin.spotify_rate_limit.duration.seconds', seconds:) if seconds.positive? || parts.empty?
      parts.join
    end

    private

    def cache_store
      @cache_store || Rails.cache
    end

    def serialize(status)
      {
        retry_after: status.retry_after,
        observed_at: status.observed_at.iso8601,
        expires_at: status.expires_at.iso8601,
        source: status.source
      }
    end

    def deserialize(payload)
      return if payload.blank?

      payload = payload.symbolize_keys
      Status.new(
        retry_after: payload.fetch(:retry_after).to_i,
        observed_at: Time.zone.parse(payload.fetch(:observed_at)),
        expires_at: Time.zone.parse(payload.fetch(:expires_at)),
        source: payload[:source]
      )
    rescue KeyError, TypeError, ArgumentError
      nil
    end
  end
end
