# frozen_string_literal: true

class ProcessYtmusicJanToAlbumBrowseIds < Avo::BaseAction
  self.name = 'JAN_TO_ALBUM_BROWSE_IDS を処理'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    result = YtmusicAlbum.process_jan_to_album_browse_ids

    message = "処理完了: 作成#{result[:created]}件, スキップ#{result[:skipped]}件, エラー#{result[:errors]}件, 未検出#{result[:missing]}件"
    succeed message
    reload
  end
end
