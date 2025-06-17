# frozen_string_literal: true

class ProcessLineMusicJanToAlbumIds < Avo::BaseAction
  self.name = 'JAN_TO_ALBUM_IDS を処理'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    created_count = 0
    updated_count = 0
    skipped_count = 0
    error_count = 0
    missing_count = 0

    # JAN_TO_ALBUM_IDS の各エントリを処理
    LineMusicAlbum::JAN_TO_ALBUM_IDS.each do |jan_code, line_music_album_id|
      # JANコードでアルバムを検索
      album = Album.find_by(jan_code: jan_code)

      if album.nil?
        missing_count += 1
        Rails.logger.warn "JAN: #{jan_code} のアルバムが見つかりません"
        next
      end

      # LINE MUSICアルバムを検索または作成
      line_music_album = LineMusicAlbum.find_by(line_music_id: line_music_album_id)

      if line_music_album.nil?
        # LINE MUSICアルバムを新規作成
        begin
          line_music_album = LineMusicAlbum.create!(
            line_music_id: line_music_album_id,
            album: album
          )
          created_count += 1
          Rails.logger.info "作成: JAN #{jan_code} → LINE MUSIC ID #{line_music_album_id}"
        rescue StandardError => e
          error_count += 1
          Rails.logger.error "エラー: JAN #{jan_code} - #{e.message}"
        end
      elsif line_music_album.album_id != album.id
        # 既存のLINE MUSICアルバムを更新
        begin
          line_music_album.update!(album: album)
          updated_count += 1
          Rails.logger.info "更新: JAN #{jan_code} → LINE MUSIC ID #{line_music_album_id}"
        rescue StandardError => e
          error_count += 1
          Rails.logger.error "エラー: JAN #{jan_code} - #{e.message}"
        end
      else
        skipped_count += 1
      end
    end

    # 簡潔な結果サマリーのみを返す
    message = "処理完了: 作成#{created_count}件, 更新#{updated_count}件, スキップ#{skipped_count}件, エラー#{error_count}件, 未検出#{missing_count}件"
    succeed message
    reload
  end
end
