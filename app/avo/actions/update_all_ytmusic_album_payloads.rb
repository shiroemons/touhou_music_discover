# frozen_string_literal: true

class UpdateAllYtmusicAlbumPayloads < Avo::BaseAction
  self.name = 'すべてのYouTube Music アルバムのペイロードを更新'
  self.visible = -> { view == :index }
  self.confirm_button_label = '更新を開始'
  self.cancel_button_label = 'キャンセル'
  self.no_confirmation = false
  self.standalone = true

  def handle(_args)
    total_count = YtmusicAlbum.count
    success_count = 0
    error_count = 0
    errors = []
    mutex = Mutex.new

    inform "#{total_count}件のアルバムのペイロード更新を開始します...(3並列で実行)"

    # バッチサイズを設定して、メモリ効率を改善
    batch_size = 100
    processed = 0

    YtmusicAlbum.find_in_batches(batch_size: batch_size) do |batch|
      # 3並列で実行
      Parallel.each(batch, in_threads: 3) do |ytmusic_album|
        current_index = nil
        mutex.synchronize do
          processed += 1
          current_index = processed
        end

        Rails.logger.info "YouTube Music アルバムのペイロードを更新 (#{current_index}/#{total_count}): #{ytmusic_album.browse_id}"

        # YouTube Music APIからアルバム情報を取得
        album = YtMusic::Album.find(ytmusic_album.browse_id)

        if album.nil?
          mutex.synchronize do
            error_count += 1
            errors << "#{ytmusic_album.name}: YouTube Musicからアルバム情報を取得できませんでした"
          end
          next
        end

        # ペイロードを更新
        url = "https://music.youtube.com/browse/#{ytmusic_album.browse_id}"
        ytmusic_album.update_album(album, url)

        mutex.synchronize do
          success_count += 1
        end
        Rails.logger.info "ペイロード更新成功: #{album.title}"

        # APIレート制限を考慮して少し待機
        sleep 0.5
      rescue StandardError => e
        mutex.synchronize do
          error_count += 1
          errors << "#{ytmusic_album.name}: #{e.message}"
        end
        Rails.logger.error "ペイロード更新エラー: #{e.class} - #{e.message}"
      end
    end

    # 結果サマリーを表示
    message = "更新完了: 成功 #{success_count}件 / エラー #{error_count}件 / 合計 #{total_count}件"

    if error_count.positive?
      message += "\n\nエラー詳細:\n"
      errors.first(10).each do |error_msg|
        message += "• #{error_msg}\n"
      end
      message += "...他#{errors.size - 10}件のエラー" if errors.size > 10
    end

    if error_count.zero?
      succeed message
    elsif success_count.positive?
      warn message
    else
      error message
    end

    reload
  end
end
