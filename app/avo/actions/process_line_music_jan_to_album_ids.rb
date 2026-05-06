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
    Admin::ActionProgress.start(
      total: LineMusicAlbum::JAN_TO_ALBUM_IDS.size,
      message: 'JAN_TO_ALBUM_IDS を処理しています'
    )

    LineMusicAlbum::JAN_TO_ALBUM_IDS.each do |jan_code, line_music_album_id|
      # JANコードでアルバムを検索
      album = Album.find_by(jan_code: jan_code)

      if album.nil?
        missing_count += 1
        Rails.logger.warn "JAN: #{jan_code} のアルバムが見つかりません"
        Admin::ActionProgress.advance(message: "JANを処理しています: #{jan_code}")
        next
      end

      # LINE MUSICアルバムを検索または作成
      line_music_album = LineMusicAlbum.find_by(line_music_id: line_music_album_id)

      if line_music_album.nil? || line_music_album.album_id != album.id
        begin
          lm_album = LineMusicAlbum.with_retry(max_attempts: 3) do
            LineMusic::Album.find(line_music_album_id)
          end

          if lm_album.blank?
            error_count += 1
            Rails.logger.warn "エラー: JAN #{jan_code} - LINE MUSIC アルバムが見つかりません: #{line_music_album_id}"
            Admin::ActionProgress.advance(message: "JANを処理しています: #{jan_code}")
            next
          end

          saved_line_music_album = LineMusicAlbum.save_album(album.id, lm_album)
          if saved_line_music_album.blank?
            error_count += 1
            Rails.logger.warn "エラー: JAN #{jan_code} - LINE MUSIC アルバム情報が不完全なため保存をスキップしました: #{line_music_album_id}"
            Admin::ActionProgress.advance(message: "JANを処理しています: #{jan_code}")
            next
          end

          if line_music_album.nil?
            created_count += 1
            Rails.logger.info "作成: JAN #{jan_code} → LINE MUSIC ID #{line_music_album_id}"
          else
            updated_count += 1
            Rails.logger.info "更新: JAN #{jan_code} → LINE MUSIC ID #{line_music_album_id}"
          end
        rescue StandardError => e
          error_count += 1
          Rails.logger.error "エラー: JAN #{jan_code} - #{e.class}: #{e.message}"
        end
      else
        skipped_count += 1
      end
      Admin::ActionProgress.advance(message: "JANを処理しています: #{jan_code}")
    end

    # 簡潔な結果サマリーのみを返す
    message = "処理完了: 作成#{created_count}件, 更新#{updated_count}件, スキップ#{skipped_count}件, エラー#{error_count}件, 未検出#{missing_count}件"
    succeed message
    reload
  end
end
