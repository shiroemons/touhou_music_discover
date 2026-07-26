# frozen_string_literal: true

# 指数バックオフ + ジッタの間隔計算を1箇所に集約する。
# Repair::YtmusicAlbumPayloads と DistributionDate::YtmusicCollector が
# 「nilや縮退レスポンスが返る間、max_attempts回までリトライする」という
# 同一の待機時間計算式(base_interval * 2**(attempt-1) * ジッタ±30%)を必要とするため。
module RetryBackoff
  # バックオフ間隔に掛けるジッタの振れ幅（±30%）。
  JITTER_RANGE = -30..30

  module_function

  # attempt: 1始まりの試行回数（1回目の失敗後に呼ばれるので実質2回目の待機時間から使う）。
  def interval(attempt, base_interval:)
    base_interval * (2**(attempt - 1)) * jitter_factor
  end

  def jitter_factor
    1 + (rand(JITTER_RANGE) / 100.0)
  end
end
