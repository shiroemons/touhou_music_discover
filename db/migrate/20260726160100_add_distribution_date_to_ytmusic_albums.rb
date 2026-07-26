# frozen_string_literal: true

class AddDistributionDateToYtmusicAlbums < ActiveRecord::Migration[8.1]
  def up
    # bulk: true で1回のALTER TABLEにまとめる（Rails/BulkChangeTable対応）
    change_table :ytmusic_albums, bulk: true do |t|
      # distributed_on: 配信日（JST）。youtube_published_on（UTC）+1日で補正した値。
      # YouTube側の公開日はUTC基準のため、JST表記の一般的な配信日と1日ずれることがあり、その補正結果を保持する
      t.date :distributed_on

      # youtube_published_on: Art Trackのpublished_on（ytmusic_tracks）の最頻値（UTCの生値）。
      # distributed_on算出のもとになった補正前の日付
      t.date :youtube_published_on

      # original_released_on: Art Trackのoriginal_released_on（ytmusic_tracks）の最頻値。
      # アルバムの原盤（CD等）リリース日として扱う
      t.date :original_released_on

      # distribution_source: 配信日をどのロジックで判定したかを示す根拠。
      # art_track_mode: Art Trackの最頻値から判定 / all_track_mode: 全トラックの最頻値から判定 /
      # single_track: 単一トラックのみで判定 / failed: 判定不能
      t.string :distribution_source

      # distribution_stats: 判定結果の監査用データ（日付ごとの件数分布、Art Track数／総トラック数、
      # 判定から除外したvideo_idなど）。判定ロジックの妥当性を後から検証できるようにするため保持する
      t.jsonb :distribution_stats

      # distribution_fetched_at: 配信日集計バッチを実行した日時。再集計要否の判定に使う
      t.datetime :distribution_fetched_at
    end

    # 配信日（JST）でのアルバム検索・並び替え用index
    add_index :ytmusic_albums, :distributed_on, name: 'index_ytmusic_albums_on_distributed_on'

    # 配信日未集計（またはNULL）のアルバムを抽出するためのindex
    add_index :ytmusic_albums, :distribution_fetched_at, name: 'index_ytmusic_albums_on_distribution_fetched_at'
  end

  def down
    remove_index :ytmusic_albums, name: 'index_ytmusic_albums_on_distribution_fetched_at'
    remove_index :ytmusic_albums, name: 'index_ytmusic_albums_on_distributed_on'

    # bulk: true で1回のALTER TABLEにまとめる（Rails/BulkChangeTable対応）
    change_table :ytmusic_albums, bulk: true do |t|
      t.remove :distribution_fetched_at
      t.remove :distribution_stats
      t.remove :distribution_source
      t.remove :original_released_on
      t.remove :youtube_published_on
      t.remove :distributed_on
    end
  end
end
