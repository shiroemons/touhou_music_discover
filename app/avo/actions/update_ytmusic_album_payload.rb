# frozen_string_literal: true

class UpdateYtmusicAlbumPayload < Avo::BaseAction
  self.name = 'YouTube Music アルバムのペイロードを更新'
  self.visible = -> { view == :show }

  def handle(**args)
    # 詳細ページから実行される場合の処理
    # modelsを優先的に使用（実際のActiveRecordモデルが含まれている）
    if args[:models].present?
      ytmusic_album = args[:models].first
    else
      # 様々なキーを試す
      resource_or_model = args[:model] || args[:record] || args[:resource] || args[:records]&.first

      # Avoリソースの場合はモデルを取得
      ytmusic_album = if resource_or_model.is_a?(YtmusicAlbumResource)
                        resource_or_model.model
                      elsif resource_or_model.is_a?(YtmusicAlbum)
                        resource_or_model
                      end
    end

    # それでも見つからない場合は、フィールドからIDを取得
    if ytmusic_album.nil?
      fields = args.values_at(:fields).first || args[:fields]
      resource_ids = fields&.dig('avo_resource_ids') || fields&.[]('avo_resource_ids')

      if resource_ids.blank?
        error("レコードが見つかりませんでした。args: #{args.keys}, fields: #{fields&.keys}")
        return
      end

      # IDからレコードを取得
      ytmusic_album = YtmusicAlbum.find(resource_ids)
    end

    begin
      Rails.logger.info "YouTube Music アルバムのペイロードを更新: #{ytmusic_album.browse_id}"

      # YouTube Music APIからアルバム情報を取得
      album = YtMusic::Album.find(ytmusic_album.browse_id)

      if album.nil?
        error('YouTube Musicからアルバム情報を取得できませんでした')
        return
      end

      # ペイロードを更新
      url = "https://music.youtube.com/browse/#{ytmusic_album.browse_id}"
      ytmusic_album.update_album(album, url)

      Rails.logger.info "ペイロード更新成功: #{album.title}"
      succeed "アルバム「#{album.title}」のペイロードを更新しました"
    rescue StandardError => e
      Rails.logger.error "ペイロード更新エラー: #{e.class} - #{e.message}"
      error "更新中にエラーが発生しました: #{e.message}"
    end

    reload
  end
end
