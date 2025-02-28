# frozen_string_literal: true

class UpdateLineMusicTrack < Avo::BaseAction
  self.name = 'Update line music track'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    Rails.logger.info 'LINE MUSIC トラック更新処理を開始します'

    album_count = LineMusicAlbum.count
    Rails.logger.info "処理対象アルバム数: #{album_count}件"

    processed_count = 0
    updated_count = 0

    LineMusicAlbum.eager_load(:line_music_tracks).find_each do |line_music_album|
      processed_count += 1
      Rails.logger.info "アルバム処理中 (#{processed_count}/#{album_count}): #{line_music_album.name}"

      begin
        with_retry(max_attempts: 3) do
          Rails.logger.info "LINE MUSIC トラック取得: アルバムID #{line_music_album.line_music_id}"
          lm_tracks = LineMusic::Album.tracks(line_music_album.line_music_id)
          Rails.logger.info "LINE MUSIC トラック取得成功: #{lm_tracks.size}件"

          track_count = line_music_album.line_music_tracks.size
          Rails.logger.info "更新対象トラック数: #{track_count}件"

          track_processed = 0
          line_music_album.line_music_tracks.each do |line_music_track|
            track_processed += 1
            Rails.logger.info "トラック処理中 (#{track_processed}/#{track_count}): #{line_music_track.name}"

            lm_track = lm_tracks.find { _1.track_id == line_music_track.line_music_id }

            if lm_track.blank?
              Rails.logger.warn "LINE MUSIC トラックが見つかりませんでした: #{line_music_track.line_music_id}"
              next
            end

            Rails.logger.info "トラック情報更新: #{lm_track.track_title}"
            line_music_track.update(
              name: lm_track.track_title,
              disc_number: lm_track.disc_number,
              track_number: lm_track.track_number,
              payload: lm_track.as_json
            )
            updated_count += 1
            Rails.logger.info "トラック情報を更新しました: #{lm_track.track_title}"
          end
        end
      rescue StandardError => e
        Rails.logger.error "アルバム処理中にエラーが発生しました: #{line_music_album.name} - #{e.message}"
      end

      Rails.logger.info "#{processed_count}件のアルバムを処理しました (更新済みトラック: #{updated_count}件)" if (processed_count % 10).zero?
    end

    Rails.logger.info "LINE MUSIC トラック更新処理が完了しました: 合計 #{processed_count}件のアルバム、#{updated_count}件のトラックを処理しました"
    succeed "処理が完了しました！ #{processed_count}件のアルバム、#{updated_count}件のトラックを処理しました。"
    reload
  end

  private

  # リトライ機能を提供するヘルパーメソッド
  def with_retry(max_attempts: 3, retry_delay: 2)
    attempts = 0
    begin
      attempts += 1
      yield
    rescue Faraday::ConnectionFailed, Net::OpenTimeout => e
      if attempts < max_attempts
        Rails.logger.warn "接続エラーが発生しました。#{attempts}回目のリトライを実行します: #{e.message}"
        sleep retry_delay * attempts # 指数バックオフ
        retry
      else
        Rails.logger.error "最大リトライ回数(#{max_attempts}回)に達しました: #{e.message}"
        raise
      end
    end
  end
end
