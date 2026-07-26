# frozen_string_literal: true

class AddVideoMetadataToYtmusicTracks < ActiveRecord::Migration[8.1]
  def up
    # bulk: true で1回のALTER TABLEにまとめる（Rails/BulkChangeTable対応）
    change_table :ytmusic_tracks, bulk: true do |t|
      # published_on: microformat.publishDate（UTCの生値）。YouTube側で公開日として扱われている日付
      t.date :published_on

      # uploaded_on: microformat.uploadDate（UTCの生値）。実際に動画がアップロードされた日付
      t.date :uploaded_on

      # original_released_on: 説明文中の「Released on: YYYY-MM-DD」から抽出した、原盤（CD等）のリリース日
      t.date :original_released_on

      # provided_by: 説明文中の「Provided to YouTube by <X>」の<X>部分。配信代行事業者名（例: Rightsscale）。
      # nilの場合は自主アップロード動画（配信代行を介さない）であることを示す
      t.string :provided_by

      # art_track: provided_byが取得できた（＝配信代行が判明した）場合にtrue。
      # 「Art Track」（配信代行によって自動生成される公式アップロード動画）かどうかの判定フラグ
      t.boolean :art_track, null: false, default: false

      # video_metadata: 配信日・Art Track判定などに使う生データ一式（channel_id/channel_name/view_count/
      # length_seconds/category/説明文冒頭数行など）。将来の再判定・デバッグのために原本を保持する
      t.jsonb :video_metadata

      # video_fetched_at: 動画メタデータ（上記各カラム）を取得した日時。未取得トラックの抽出や再取得判定に使う
      t.datetime :video_fetched_at
    end

    # アルバム単位で公開日を集計する処理（配信日推定バッチ等）向けの複合index
    add_index :ytmusic_tracks, %i[ytmusic_album_id published_on],
              name: 'index_ytmusic_tracks_on_ytmusic_album_id_and_published_on'

    # 動画メタデータ未取得（またはNULL）のトラックを抽出するためのindex
    add_index :ytmusic_tracks, :video_fetched_at, name: 'index_ytmusic_tracks_on_video_fetched_at'
  end

  def down
    remove_index :ytmusic_tracks, name: 'index_ytmusic_tracks_on_video_fetched_at'
    remove_index :ytmusic_tracks, name: 'index_ytmusic_tracks_on_ytmusic_album_id_and_published_on'

    # bulk: true で1回のALTER TABLEにまとめる（Rails/BulkChangeTable対応）
    change_table :ytmusic_tracks, bulk: true do |t|
      t.remove :video_fetched_at
      t.remove :video_metadata
      t.remove :art_track
      t.remove :provided_by
      t.remove :original_released_on
      t.remove :uploaded_on
      t.remove :published_on
    end
  end
end
