# frozen_string_literal: true

class UpdateLineMusicAlbum < Avo::BaseAction
  self.name = 'LINE MUSIC アルバムを更新'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    updated_count = 0
    error_count = 0

    LineMusicAlbum.find_each do |line_music_album|
      Rails.logger.info "Fetching LINE MUSIC album: #{line_music_album.line_music_id}"
      lm_album = LineMusic::Album.find(line_music_album.line_music_id)

      if lm_album.present?
        line_music_album.update(
          name: lm_album.album_title,
          total_tracks: lm_album.track_total_count,
          payload: lm_album.as_json
        )
        updated_count += 1
      end
    rescue Faraday::ConnectionFailed => e
      Rails.logger.error "Connection failed for album #{line_music_album.line_music_id}: #{e.message}"
      error_count += 1
    rescue Faraday::TimeoutError => e
      Rails.logger.error "Timeout for album #{line_music_album.line_music_id}: #{e.message}"
      error_count += 1
    rescue StandardError => e
      Rails.logger.error "Error updating album #{line_music_album.line_music_id}: #{e.class} - #{e.message}"
      error_count += 1
    end

    if error_count.positive?
      warn "更新完了: #{updated_count}件成功、#{error_count}件エラー"
    else
      succeed "更新完了: #{updated_count}件成功"
    end
    reload
  end
end
