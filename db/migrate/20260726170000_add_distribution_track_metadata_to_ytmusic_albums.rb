# frozen_string_literal: true

class AddDistributionTrackMetadataToYtmusicAlbums < ActiveRecord::Migration[8.1]
  def up
    # distribution_track_metadata: ytmusic_albums.payload['tracks']のvideo_idを正として取得した、
    # 動画1本ごとの取得結果一覧（配列）。ytmusic_tracksの行はアルバム取り込みより遅れて作られるため、
    # 行の有無に依存せず配信日を集計・再取得できるよう、アルバム側にも一次データを保持する。
    # 取得に失敗した動画も published_on 等を null にした要素として記録し、fetched_at で
    # 「いつ何を試したか」を追えるようにする。
    add_column :ytmusic_albums, :distribution_track_metadata, :jsonb
  end

  def down
    remove_column :ytmusic_albums, :distribution_track_metadata
  end
end
